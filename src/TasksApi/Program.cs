using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// Строка подключения собирается из переменных окружения, переданных в docker-compose.yml.
// Host = имя сервиса db в сети Docker Compose.
var host     = Environment.GetEnvironmentVariable("DB_HOST")     ?? "localhost";
var port     = Environment.GetEnvironmentVariable("DB_PORT")     ?? "5432";
var database = Environment.GetEnvironmentVariable("DB_NAME")     ?? "app";
var user     = Environment.GetEnvironmentVariable("DB_USER")     ?? "postgres";
var password = Environment.GetEnvironmentVariable("DB_PASSWORD") ?? "1234";

var connectionString = $"Host={host};Port={port};Database={database};Username={user};Password={password}";

builder.Services.AddDbContext<AppDbContext>(o => o.UseNpgsql(connectionString));

var app = builder.Build();

// Создаём таблицу при старте. Повторяем попытки, пока PostgreSQL не будет готов.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
    for (var attempt = 1; ; attempt++)
    {
        try
        {
            db.Database.EnsureCreated();
            logger.LogInformation("Connected to PostgreSQL at {Host}:{Port}/{Db}", host, port, database);
            break;
        }
        catch (Exception ex) when (attempt < 30)
        {
            logger.LogWarning("PostgreSQL is not ready (attempt {Attempt}): {Message}", attempt, ex.Message);
            Thread.Sleep(2000);
        }
    }
}

app.MapGet("/", () => Results.Ok(new { service = "tasks-api", status = "ok" }));

var tasks = app.MapGroup("/api/tasks");

// READ: все задачи
tasks.MapGet("/", async (AppDbContext db) =>
    await db.Tasks.OrderBy(t => t.Id).ToListAsync());

// READ: одна задача
tasks.MapGet("/{id:int}", async (int id, AppDbContext db) =>
    await db.Tasks.FindAsync(id) is { } task ? Results.Ok(task) : Results.NotFound());

// CREATE
tasks.MapPost("/", async (TaskInput input, AppDbContext db) =>
{
    if (string.IsNullOrWhiteSpace(input.Title))
        return Results.BadRequest(new { error = "Title is required" });

    var task = new TaskItem
    {
        Title = input.Title,
        Description = input.Description,
        IsCompleted = input.IsCompleted ?? false,
        CreatedAt = DateTime.UtcNow
    };
    db.Tasks.Add(task);
    await db.SaveChangesAsync();
    return Results.Created($"/api/tasks/{task.Id}", task);
});

// UPDATE
tasks.MapPut("/{id:int}", async (int id, TaskInput input, AppDbContext db) =>
{
    var task = await db.Tasks.FindAsync(id);
    if (task is null) return Results.NotFound();
    if (string.IsNullOrWhiteSpace(input.Title))
        return Results.BadRequest(new { error = "Title is required" });

    task.Title = input.Title;
    task.Description = input.Description;
    task.IsCompleted = input.IsCompleted ?? task.IsCompleted;
    await db.SaveChangesAsync();
    return Results.Ok(task);
});

// DELETE
tasks.MapDelete("/{id:int}", async (int id, AppDbContext db) =>
{
    var task = await db.Tasks.FindAsync(id);
    if (task is null) return Results.NotFound();
    db.Tasks.Remove(task);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

app.Run();

public class TaskItem
{
    public int Id { get; set; }
    public string Title { get; set; } = "";
    public string? Description { get; set; }
    public bool IsCompleted { get; set; }
    public DateTime CreatedAt { get; set; }
}

public record TaskInput(string Title, string? Description, bool? IsCompleted);

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<TaskItem> Tasks => Set<TaskItem>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<TaskItem>(e =>
        {
            e.ToTable("tasks");
            e.Property(t => t.Id).HasColumnName("id");
            e.Property(t => t.Title).HasColumnName("title").HasMaxLength(200).IsRequired();
            e.Property(t => t.Description).HasColumnName("description");
            e.Property(t => t.IsCompleted).HasColumnName("is_completed");
            e.Property(t => t.CreatedAt).HasColumnName("created_at");
        });
    }
}
