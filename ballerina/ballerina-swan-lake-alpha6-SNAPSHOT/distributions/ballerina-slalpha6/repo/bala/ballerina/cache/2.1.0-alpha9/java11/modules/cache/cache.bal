// Copyright (c) 2020 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/jballerina.java;
import ballerina/task;
import ballerina/time;

# Represents configurations for the `cache:Cache` object.
#
# + capacity - Maximum number of entries allowed in the cache
# + evictionFactor - The factor by which the entries will be evicted once the cache is full
# + evictionPolicy - The policy which is used to evict entries once the cache is full
# + defaultMaxAge - The default value in seconds which all the cache entries are valid. '-1' means, the entries are
#                   valid forever. This will be overwritten by the the `maxAge` property set when inserting item to
#                   the cache
# + cleanupInterval - Interval (in seconds) of the timer task, which will clean up the cache
public type CacheConfig record {|
    int capacity = 100;
    float evictionFactor = 0.25;
    EvictionPolicy evictionPolicy = LRU;
    decimal defaultMaxAge = -1;
    decimal cleanupInterval?;
|};

# Possible types of eviction policy that can be passed into the `EvictionPolicy`
public enum EvictionPolicy {
    LRU
}

type CacheEntry record {|
    string key;
    any data;
    decimal expTime;  // exp time since epoch. calculated based on the `maxAge` parameter when inserting to map
|};

// Cleanup service which cleans the cache entries periodically.
boolean cleanupInProgress = false;

class Cleanup {

    *task:Job;
    private LinkedList linkedList;
    private Cache cache;

    public function execute() {
        // This check will skip the processes triggered while the clean up in progress.
        if (!cleanupInProgress) {
            cleanupInProgress = true;
            cleanup(self.cache, self.linkedList);
            cleanupInProgress = false;
        }
    }

    public isolated function init(Cache cache, LinkedList linkedList) {
        self.linkedList = linkedList;
        self.cache = cache;
    }
}

# The `cache:Cache` object, which is used for all the cache-related operations. It is not recommended to insert `()`
# as the value of the cache since it doesn't make any sense to cache a nil.
public class Cache {

    *AbstractCache;

    private int maxCapacity;
    private EvictionPolicy evictionPolicy;
    private float evictionFactor;
    private decimal defaultMaxAge;
    private LinkedList linkedList;

    # Called when a new `cache:Cache` object is created.
    # ```ballerina
    # cache:Cache cache = new({capacity: 10, evictionFactor: 0.2});
    # ```
    #
    # + cacheConfig - Configurations for the `cache:Cache` object
    public isolated function init(CacheConfig cacheConfig = {}) {
        self.maxCapacity = cacheConfig.capacity;
        self.evictionPolicy = cacheConfig.evictionPolicy;
        self.evictionFactor = cacheConfig.evictionFactor;
        self.defaultMaxAge =  cacheConfig.defaultMaxAge;
        self.linkedList = new LinkedList();

        // Cache capacity must be a positive value.
        if (self.maxCapacity <= 0) {
            panic prepareError("Capacity must be greater than 0.");
        }
        // Cache eviction factor must be between 0.0 (exclusive) and 1.0 (inclusive).
        if (self.evictionFactor <= 0.0 || self.evictionFactor > 1.0) {
            panic prepareError("Cache eviction factor must be between 0.0 (exclusive) and 1.0 (inclusive).");
        }

        // Cache eviction factor must be between 0.0 (exclusive) and 1.0 (inclusive).
        if (self.defaultMaxAge != -1d && self.defaultMaxAge <= 0d) {
            panic prepareError("Default max age should be greater than 0 or -1 for indicate forever valid.");
        }

        externLockInit();
        externInit(self, self.maxCapacity);

        decimal? interval = cacheConfig?.cleanupInterval;
        if (interval is decimal) {
            time:Utc currentUtc = time:utcNow();
            time:Utc newTime = time:utcAddSeconds(currentUtc, interval);
            time:Civil time = time:utcToCivil(newTime);
            var result = task:scheduleJobRecurByFrequency(new Cleanup(self, self.linkedList), interval,
                                        startTime = time);
            if (result is task:Error) {
                string message = string `Failed to schedule the cleanup task: ${result.message()}`;
                panic prepareError(message);
            }
        }
    }

    # Adds the given key value pair to the cache. If the cache previously contained a value associated with the
    # provided key, the old value wil be replaced by the newly-provided value.
    # ```ballerina
    # cache:Error? result = cache.put("Hello", "Ballerina");
    # ```
    #
    # + key - Key of the value to be cached
    # + value - Value to be cached. Value should not be `()`
    # + maxAge - The time in seconds for which the cache entry is valid. If the value is '-1', the entry is
    #                     valid forever.
    # + return - `()` if successfully added to the cache or `Error` if a `()` value is inserted to the cache.
    public isolated function put(string key, any value, decimal maxAge = -1) returns Error? {
        if (value is ()) {
            return prepareError("Unsupported cache value '()' for the key: " + key + ".");
        }
        // If the current cache is full (i.e. size = capacity), evict cache.
        if (self.size() == self.maxCapacity) {
            evict(self, self.maxCapacity, self.evictionFactor, self.linkedList);
        }
        time:Utc currentUtc = time:utcNow();
        // Calculate the `expTime` of the cache entry based on the `maxAgeInSeconds` property and
        // `defaultMaxAge` property.
        decimal calculatedExpTime = -1;
        if (maxAge != -1d && maxAge > 0d) {
            time:Utc newTime = time:utcAddSeconds(currentUtc, <decimal> maxAge);
            calculatedExpTime = <decimal>newTime[0] + newTime[1];
        } else {
            if (self.defaultMaxAge != -1d) {
                time:Utc newTime = time:utcAddSeconds(currentUtc, <decimal> self.defaultMaxAge);
                calculatedExpTime = <decimal>newTime[0] + newTime[1];
            }
        }

        CacheEntry entry = {
            key: key,
            data: value,
            expTime: calculatedExpTime
        };
        Node newNode = { value: entry };

        if (self.hasKey(key)) {
            Node oldNode = externGet(self, key);
            // Move the node to front
            self.linkedList.remove(oldNode);
            self.linkedList.addFirst(newNode);
        } else {
            self.linkedList.addFirst(newNode);
        }
        externPut(self, key, newNode);
    }

    # Returns the cached value associated with the provided key.
    # ```ballerina
    # any|cache:Error value = cache.get(key);
    # ```
    #
    # + key - Key of the cached value, which should be retrieved
    # + return - The cached value associated with the provided key or an `Error` if the provided cache key is not
    #            exisiting in the cache or any error occurred while retrieving the value from the cache.
    public isolated function get(string key) returns any|Error {
        if (!self.hasKey(key)) {
            return prepareError("Cache entry from the given key: " + key + ", is not available.");
        }

        Node node = externGet(self, key);
        CacheEntry entry = <CacheEntry>node.value;

        // Check whether the cache entry is already expired. Even though the cache cleaning task is configured
        // and runs in predefined intervals, sometimes the cache entry might not have been removed at this point
        // even though it is expired. So this check guarantees that the expired cache entries will not be returned.
        time:Utc currentUtc = time:utcNow();
        if (entry.expTime != -1d && entry.expTime < (<decimal>currentUtc[0] + currentUtc[1])) {
            self.linkedList.remove(node);
            externRemove(self, key);
            return ();
        }
        // Move the node to front
        self.linkedList.remove(node);
        self.linkedList.addFirst(node);
        return entry.data;
    }

    # Discards a cached value from the cache.
    # ```ballerina
    # cache:Error? result = cache.invalidate(key);
    # ```
    #
    # + key - Key of the cache value, which needs to be discarded from the cache
    # + return - `()` if successfully discarded the value or an `Error` if the provided cache key is not present in the
    #            cache
    public isolated function invalidate(string key) returns Error? {
        if (!self.hasKey(key)) {
            return prepareError("Cache entry from the given key: " + key + ", is not available.");
        }

        Node node = externGet(self, key);
        self.linkedList.remove(node);
        externRemove(self, key);
    }

    # Discards all the cached values from the cache.
    # ```ballerina
    # cache:Error? result = cache.invalidateAll();
    # ```
    #
    # + return - `()` if successfully discarded all the values from the cache or an `Error` if any error occurred while
    # discarding all the values from the cache.
    public isolated function invalidateAll() returns Error? {
        self.linkedList.clear();
        externRemoveAll(self);
    }

    # Checks whether the given key has an associated cached value.
    # ```ballerina
    # boolean result = cache.hasKey(key);
    # ```
    #
    # + key - The key to be checked in the cache
    # + return - `true` if a cached value is available for the provided key or `false` if there is no cached value
    #            associated for the given key
    public isolated function hasKey(string key) returns boolean {
        return externHasKey(self, key);
    }

    # Returns a list of all the keys from the cache.
    # ```ballerina
    # string[] keys = cache.keys();
    # ```
    #
    # + return - Array of all the keys from the cache
    public isolated function keys() returns string[] {
        return externKeys(self);
    }

    # Returns the size of the cache.
    # ```ballerina
    # int result = cache.size();
    # ```
    #
    # + return - The size of the cache
    public isolated function size() returns int {
        return externSize(self);
    }

    # Returns the capacity of the cache.
    # ```ballerina
    # int result = cache.capacity();
    # ```
    #
    # + return - The capacity of the cache
    public isolated function capacity() returns int {
        return self.maxCapacity;
    }
}

isolated function evict(Cache cache, int capacity, float evictionFactor, LinkedList linkedList) {
    int evictionKeysCount = <int>(capacity * evictionFactor);
    foreach int i in 1...evictionKeysCount {
        Node? node = linkedList.removeLast();
        if (node is Node) {
            CacheEntry entry = <CacheEntry>node.value;
            externRemove(cache, entry.key);
            // The return result (error which occurred due to unavailability of the key or nil) is ignored
            // since no purpose of handling it.
        } else {
            break;
        }
    }
}

isolated function cleanup(Cache cache, LinkedList linkedList) {
    string[] keys = cache.keys();
    if (keys.length() == 0) {
        return;
    }
    foreach string key in keys {
        Node node = externGet(cache, key);
        CacheEntry entry = <CacheEntry>node.value;
        time:Utc currentUtc = time:utcNow();
        if (entry.expTime != -1d && entry.expTime < (<decimal>currentUtc[0] + currentUtc[1])) {
            linkedList.remove(node);
            externRemove(cache, entry.key);
            // The return result (error which occurred due to unavailability of the key or nil) is ignored
            // since no purpose of handling it.
            return;
        }
    }
}

isolated function externInit(Cache cache, int capacity) = @java:Method {
    'class: "org.ballerinalang.stdlib.cache.nativeimpl.Cache"
} external;

isolated function externPut(Cache cache, string key, Node value) = @java:Method {
    'class: "org.ballerinalang.stdlib.cache.nativeimpl.Cache"
} external;

isolated function externGet(Cache cache, string key) returns Node = @java:Method {
    'class: "org.ballerinalang.stdlib.cache.nativeimpl.Cache"
} external;

isolated function externRemove(Cache cache, string key) = @java:Method {
    'class: "org.ballerinalang.stdlib.cache.nativeimpl.Cache"
} external;

isolated function externRemoveAll(Cache cache) = @java:Method {
    'class: "org.ballerinalang.stdlib.cache.nativeimpl.Cache"
} external;

isolated function externHasKey(Cache cache, string key) returns boolean = @java:Method {
    'class: "org.ballerinalang.stdlib.cache.nativeimpl.Cache"
} external;

isolated function externKeys(Cache cache) returns string[] = @java:Method {
    'class: "org.ballerinalang.stdlib.cache.nativeimpl.Cache"
} external;

isolated function externSize(Cache cache) returns int = @java:Method {
    'class: "org.ballerinalang.stdlib.cache.nativeimpl.Cache"
} external;
