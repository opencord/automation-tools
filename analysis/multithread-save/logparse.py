# Copyright 2019-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/usr/bin/python

from pyparsing import Combine, Group, Optional, ParseException, Regex, Word, ZeroOrMore, alphas, nums
import fileinput
import pprint

Written = {}

Date = Combine(Word(nums)+"-"+Word(nums)+"-"+Word(nums))
Time = Combine(Word(nums)+":"+Word(nums)+":"+Word(nums)+"."+Word(nums))
Msg = Regex("is new|no changes|updated")
QuotedWord = "'"+Word(alphas+"_")+"'"+Optional(", ")
Array = "["+ZeroOrMore(QuotedWord)+"]"
Key = Word(alphas+"_")
Value = Array | Word(alphas+"_-/.")
KeyValue = Combine(Key("key")+"="+Value("value"))
Logmsg = Date+"T"+Time+"Z [debug    ] save(): "+Msg+KeyValue*(2,3)

entries = {}

def add_syncstep(model, field, syncstep):
    if model not in entries:
        entries[model] = {}
    if field in entries[model]:
        if syncstep not in entries[model][field]:
            entries[model][field].append(syncstep)
    else:
        entries[model][field] = [syncstep]


for line in fileinput.input():
    entry = {}
    try:
        logline = Logmsg.parseString(line)
        #print logline
        entry["status"] = logline[4]
        for field in range(5, len(logline)):
            key, value = logline[field].split("=")
            if key == "changed_fields":
                entry[key] = eval(value)
            else:
                entry[key] = value

        if entry["syncstep"] == "None":
            continue

        if "changed_fields" in entry:
            for field in entry["changed_fields"]:
                add_syncstep(entry["classname"], field, entry["syncstep"])
        else:
            if entry["status"] == "no changes":
                add_syncstep(entry["classname"], "all", entry["syncstep"])


    except ParseException, err:
        print err.line
        print " "*(err.column-1) + "^"
        print err

pp = pprint.PrettyPrinter()

for obj in entries:
    all_syncstep = []
    print "\nInspecting model: ", obj
    entry = entries[obj]
    if "all" in entry:
        print "  [WARNING] Object being saved with no changes"
        all_syncstep = entry["all"]
        for path in all_syncstep:
            print "    ", path
    for field in entry:
        if field == "all":
            continue
        syncstep = list(set(entry[field] + all_syncstep))
        if len(syncstep) > 1:
            print "  [WARNING] Field saved from multiple tasks: ", field
            for path in syncstep:
                print "    ", path
