# Copyright 2019-present the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Separate the incoming stream of messages from kafkacat and call
# protoc on each message.

from __future__ import print_function

import subprocess
import sys


def call_protoc(buf, msgName, protoFileName, includeDir, first):
    process = subprocess.Popen(["protoc", "--decode="+msgName, protoFileName, "-I", includeDir], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    process.stdin.write(buf)
    if not first:
        print(",")
    print(process.communicate()[0].decode("utf-8"))
    process.stdin.close()


def main():
    if len(sys.argv) != 4:
        print(sys.stderr, "syntax: callprotoc.py <msgname> <protofilename> <includedir>", file=sys.stderr)
        sys.exit(-1)

    msgName = sys.argv[1]
    protoFileName = sys.argv[2]
    includeDir = sys.argv[3]

    print ("[")

    buf = b""
    first = True
    in_bytes = sys.stdin.buffer.read(1)
    while in_bytes:
        buf = buf + in_bytes
        while b"===VOLTHA-DELIM===" in buf:
            (part, buf) = buf.split(b"===VOLTHA-DELIM===", 1)
            if first:
                first = False
            call_protoc(part, msgName, protoFileName, includeDir, first)
        in_bytes = sys.stdin.buffer.read(1)

    # there is likely one trailing message still to print
    if buf:
        call_protoc(buf, msgName, protoFileName, includeDir, first)

    print ("]")


if __name__ == "__main__":
    main()
