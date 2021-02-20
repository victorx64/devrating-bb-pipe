FROM mcr.microsoft.com/dotnet/sdk:5.0-alpine

RUN apk add --update --no-cache jq
RUN dotnet tool install -g devrating.consoleapp --version 3.2.0

COPY script.sh /

ENTRYPOINT ["/script.sh"]
