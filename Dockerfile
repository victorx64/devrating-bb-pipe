FROM mcr.microsoft.com/dotnet/sdk:5.0-alpine as builder

RUN dotnet tool install -g devrating.consoleapp --version 3.2.0

# Use the smaller runtime image
FROM mcr.microsoft.com/dotnet/runtime:5.0-alpine

RUN apk add --update --no-cache jq
RUN apk add --no-cache curl
RUN apk add --no-cache git

# Copy the binaries across, and set the path
COPY --from=builder /root/.dotnet/tools/ /opt/bin

ENV PATH="/opt/bin:${PATH}"

COPY script.sh /

ENTRYPOINT ["/script.sh"]
