// Copyright (c) 2021 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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

# Generates a random decimal number between 0.0 and 1.0.
# ```ballerina
# float randomValue = random:createDecimal();
# ```
# 
# + return - Selected random value
public isolated function createDecimal() returns float = @java:Method {
    name: "random",
    'class: "java.lang.Math"
} external;

# Generates a random number between the given start(inclusive) and end(exclusive) values.
# ```ballerina
# int|error randomInteger = random:createIntInRange(1, 100);
# ```
# 
# + startRange - Range start value
# + endRange - Range end value
# + return - Selected random value or else `Error` if start range is greater than the end range
public isolated function createIntInRange(int startRange, int endRange) returns int|Error = @java:Method {
    name: "randomInRange",
    'class: "org.ballerinalang.stdlib.random.nativeimpl.ExternMethods"
} external;
