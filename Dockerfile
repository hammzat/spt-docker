FROM mcr.microsoft.com/dotnet/aspnet:10.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends 7zip unzip curl ca-certificates jq rsync \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /opt/spt/server
EXPOSE 6969
ENTRYPOINT ["/entrypoint.sh"]
