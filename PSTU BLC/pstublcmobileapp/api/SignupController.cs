using Microsoft.AspNetCore.Mvc;
using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using MySql.Data.MySqlClient;

namespace PstuBlcApi.Controllers
{
    [ApiController]
    [Route("api")]
    [EnableCors("AllowFrontend")]
    public class SignupController : ControllerBase
    {
        private readonly IConfiguration _configuration;

        public SignupController(IConfiguration configuration)
        {
            _configuration = configuration;
        }

        public class SignupRequest
        {
            public string Name { get; set; }
            public string Email { get; set; }
            public string Phone { get; set; }
            public string Category { get; set; }
            public string Hex { get; set; }
            public string Password { get; set; }
            public string ConfirmPassword { get; set; }
        }

        public class SignupResponse
        {
            public bool Success { get; set; }
            public string Message { get; set; }
            public Dictionary<string, string> Errors { get; set; }
        }

        [HttpPost("signup")]
        public async Task<ActionResult<SignupResponse>> Signup([FromBody] SignupRequest request)
        {
            var errors = new Dictionary<string, string>();

            if (string.IsNullOrWhiteSpace(request.Name))
            {
                errors["name"] = "Name is required";
            }
            else if (request.Name.Length < 3 || request.Name.Length > 15)
            {
                errors["name"] = "Name must be 3-15 characters";
            }

            if (string.IsNullOrWhiteSpace(request.Email))
            {
                errors["email"] = "Email is required";
            }
            else if (request.Category?.ToLower() == "student")
            {
                var emailValidation = Services.EmailValidationService.ValidateStudentEmail(request.Email);
                if (!emailValidation.Valid)
                {
                    errors["email"] = emailValidation.Error;
                }
            }

            if (string.IsNullOrWhiteSpace(request.Phone))
            {
                errors["phone"] = "Phone is required";
            }
            else if (!Regex.IsMatch(request.Phone, @"^(\+?88)?01[0-9]{9}$"))
            {
                errors["phone"] = "Invalid phone format. Must be 01xxxxxxxxx";
            }

            if (request.Category?.ToLower() != "student" && request.Category?.ToLower() != "teacher")
            {
                errors["category"] = "Invalid category selected";
            }

            if (request.Category?.ToLower() == "teacher")
            {
                if (string.IsNullOrWhiteSpace(request.Hex))
                {
                    errors["hex"] = "Hex code is required for teachers";
                }
            }

            if (string.IsNullOrWhiteSpace(request.Password))
            {
                errors["password"] = "Password is required";
            }
            else if (request.Password.Length < 3)
            {
                errors["password"] = "Password must be at least 3 characters";
            }

            if (request.Password != request.ConfirmPassword)
            {
                errors["password"] = "Passwords do not match";
            }

            if (errors.Count > 0)
            {
                return BadRequest(new SignupResponse
                {
                    Success = false,
                    Message = errors.Values.First(),
                    Errors = errors
                });
            }

            var passwordHash = HashPassword(request.Password);

            try
            {
                var connectionString = _configuration.GetConnectionString("DefaultConnection");
                using (var connection = new MySqlConnection(connectionString))
                {
                    await connection.OpenAsync();

                    if (request.Category.ToLower() == "teacher")
                    {
                        int? hexId = null;
                        using (var getHexCmd = new MySqlCommand("SELECT id FROM teacher_hex_codes WHERE hex_code = @hex", connection))
                        {
                            getHexCmd.Parameters.AddWithValue("@hex", request.Hex);
                            var result = await getHexCmd.ExecuteScalarAsync();
                            if (result == null)
                            {
                                errors["hex"] = "Invalid HEX code";
                                return BadRequest(new SignupResponse { Success = false, Message = errors["hex"], Errors = errors });
                            }
                            hexId = Convert.ToInt32(result);
                        }

                        using (var checkCmd = new MySqlCommand("SELECT COUNT(*) FROM teachers WHERE hex_code_id = @hexId", connection))
                        {
                            checkCmd.Parameters.AddWithValue("@hexId", hexId);
                            var used = Convert.ToInt32(await checkCmd.ExecuteScalarAsync());
                            if (used > 0)
                            {
                                errors["hex"] = "HEX code already used";
                                return BadRequest(new SignupResponse { Success = false, Message = errors["hex"], Errors = errors });
                            }
                        }

                        var query = "INSERT INTO teachers (name, email, phone, password_hash, hex_code_id) VALUES (@name, @email, @phone, @password, @hexId)";
                        using (var command = new MySqlCommand(query, connection))
                        {
                            command.Parameters.AddWithValue("@name", request.Name);
                            command.Parameters.AddWithValue("@email", request.Email.ToLower());
                            command.Parameters.AddWithValue("@phone", request.Phone);
                            command.Parameters.AddWithValue("@password", passwordHash);
                            command.Parameters.AddWithValue("@hexId", hexId);

                            try
                            {
                                await command.ExecuteNonQueryAsync();
                                return Ok(new SignupResponse
                                {
                                    Success = true,
                                    Message = "Teacher registration successful"
                                });
                            }
                            catch (MySqlException ex) when (ex.Number == 1062)
                            {
                                return BadRequest(new SignupResponse
                                {
                                    Success = false,
                                    Message = "Email or HEX already registered"
                                });
                            }
                        }
                    }
                    else
                    {
                        var emailValidation = Services.EmailValidationService.ValidateStudentEmail(request.Email);
                        var faculty = emailValidation.Faculty;
                        var table = faculty.Table;

                        var query = $"INSERT INTO {table} (name, email, phone, password_hash) VALUES (@name, @email, @phone, @password)";
                        using (var command = new MySqlCommand(query, connection))
                        {
                            command.Parameters.AddWithValue("@name", request.Name);
                            command.Parameters.AddWithValue("@email", request.Email.ToLower());
                            command.Parameters.AddWithValue("@phone", request.Phone);
                            command.Parameters.AddWithValue("@password", passwordHash);

                            try
                            {
                                await command.ExecuteNonQueryAsync();
                                return Ok(new SignupResponse
                                {
                                    Success = true,
                                    Message = "Student registration successful"
                                });
                            }
                            catch (MySqlException ex) when (ex.Number == 1062)
                            {
                                return BadRequest(new SignupResponse
                                {
                                    Success = false,
                                    Message = "Email already registered"
                                });
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                return StatusCode(500, new SignupResponse
                {
                    Success = false,
                    Message = $"Database error: {ex.Message}"
                });
            }
        }

        [HttpGet("health")]
        public ActionResult Health()
        {
            return Ok(new { status = "ok" });
        }

        private string HashPassword(string password)
        {
            using (var sha256 = SHA256.Create())
            {
                var hashedBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(password));
                return Convert.ToBase64String(hashedBytes);
            }
        }
    }
}
