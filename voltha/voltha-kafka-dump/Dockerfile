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

FROM confluentinc/cp-kafkacat:4.1.2

# version of voltha-protos to use in this container

ARG VOLTHA_PROTOS_VERSION=unknown

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y unzip=6.0-21+deb9u2 curl=7.52.1-5+deb9u10 git=1:2.11.0-3+deb9u7 libatomic1=6.3.0-18+deb9u1 ca-certificates=20161130+nmu1+deb9u1 python3.5=3.5.3-1+deb9u2 --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install protoc
RUN PROTOC_VERSION="3.7.0" && \
    PROTOC_SHA256SUM="a1b8ed22d6dc53c5b8680a6f1760a305b33ef471bece482e92728f00ba2a2969" && \
    curl -L -o /tmp/protoc-$PROTOC_VERSION-linux-x86_64.zip https://github.com/google/protobuf/releases/download/v$PROTOC_VERSION/protoc-$PROTOC_VERSION-linux-x86_64.zip && \
    echo "$PROTOC_SHA256SUM  /tmp/protoc-$PROTOC_VERSION-linux-x86_64.zip" | sha256sum -c - && \
    unzip /tmp/protoc-$PROTOC_VERSION-linux-x86_64.zip -d /tmp/protoc3 && \
    mv /tmp/protoc3/bin/* /usr/local/bin/ && \
    mv /tmp/protoc3/include/* /usr/local/include/ && \
    chmod -R a+rx /usr/local/bin/* && \
    chmod -R a+rX /usr/local/include/

WORKDIR /opt/voltha-kafka-dump

# Install voltha-protos
RUN git clone -b $VOLTHA_PROTOS_VERSION --single-branch https://github.com/opencord/voltha-protos.git

COPY callprotoc.py voltha-dump-events.sh ./
