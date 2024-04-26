FROM mcr.microsoft.com/playwright:v1.43.1-jammy AS playwright
FROM koalaman/shellcheck:v0.10.0 AS shellcheck
FROM maven:3.9.6-eclipse-temurin-11 AS maven
FROM groovy:3.0.9-jre8 AS groovy
FROM cloudbees/cloudbees-core-agent:2.440.3.7 AS base
# kaniko does not set TARGETARCH as a build arg
ARG TARGETARCH=amd64
# when building we need to ensure that the workingDir is not /home/jenkins otherwise kaniko will not whitelist the directory
# and changes will get lost

# Known hosts for SSH
RUN mkdir -p /home/jenkins/.ssh && \
    echo "github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=" >> /home/jenkins/.ssh/known_hosts

USER root
RUN dnf -y update && \
    dnf -y install \
      java-1.8.0-openjdk-devel \
      java-11-openjdk-devel  \
      java-17-openjdk-devel \
      jq \
      unzip \
      libX11-xcb \
      mesa-libgbm \
      libdrm \
      xz && \
    dnf -y clean all

# Required for git commit signing
# dnf package is 8.0 which comes with an older ssh-keygen version. Compiling was the last resort, nothing else worked
# ssh-keygen -Y option is needed and 8.2 provides it
RUN curl https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-8.2p1.tar.gz -o openssh-8.2p1.tar.gz && \
    tar -xzf openssh-8.2p1.tar.gz && \
    cd openssh-8.2p1 && \
    dnf -y install gcc zlib-devel openssl-devel make && \
    ./configure && make && make install && \
    cd .. && rm -rf openssh-8.2p1 && rm openssh-8.2p1.tar.gz && \
    dnf -y remove gcc zlib-devel openssl-devel make && \
    dnf -y clean all

ENV JAVA8_HOME /usr/lib/jvm/java-1.8.0-openjdk
ENV JAVA11_HOME /usr/lib/jvm/java-11-openjdk
ENV JAVA17_HOME /usr/lib/jvm/java-17-openjdk
RUN "$JAVA8_HOME/bin/java" -version && \
    "$JAVA11_HOME/bin/java" -version && \
    "$JAVA17_HOME/bin/java" -version

COPY --from=shellcheck /bin/shellcheck /usr/local/bin/shellcheck
# Needed for cloudbees-update-center tests which rely on RSA key of 1024 bits
RUN update-crypto-policies --set LEGACY

ENV GH_VERSION=2.40.0
RUN curl -sSL -o gh.rpm https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.rpm && \
    rpm -i gh.rpm && \
    rm gh.rpm && \
    gh --version

COPY --from=groovy /opt/groovy /opt/groovy
RUN ln -s /opt/groovy/bin/groovy /usr/local/bin/groovy

COPY --from=maven /usr/share/maven /usr/share/maven/
RUN ln -s /usr/share/maven/bin/mvn /usr/local/bin/mvn && \
    ln -s /usr/share/maven/bin/mvnDebug /usr/local/bin/mvnDebug

COPY --from=playwright --chown=jenkins:jenkins /ms-playwright /ms-playwright
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

FROM base AS jdk8
RUN alternatives --set java java-1.8.0-openjdk.$(arch) && \
    alternatives --set javac java-1.8.0-openjdk.$(arch)
USER 1000
RUN java -version && \
    javac -version && \
    mvn --version && \
    groovy --version && \
    gh --version

FROM base AS jdk11
RUN alternatives --set java java-11-openjdk.$(arch) && \
    alternatives --set javac java-11-openjdk.$(arch)
USER 1000
RUN java -version && \
    javac -version && \
    mvn --version && \
    groovy --version && \
    gh --version

FROM base AS jdk17
RUN alternatives --set java java-17-openjdk.$(arch) && \
    alternatives --set javac java-17-openjdk.$(arch)
USER 1000
RUN java -version && \
    javac -version && \
    mvn --version && \
    groovy --version && \
    gh --version
