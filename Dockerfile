# --- Сборка ---
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/TasksApi/TasksApi.csproj ./
RUN dotnet restore
COPY src/TasksApi/ ./
RUN dotnet publish -c Release -o /app --no-restore

# --- Запуск ---
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app ./
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "TasksApi.dll"]
