using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace PstuBlcApi.Services
{
    public class EmailValidationService
    {
        private static readonly Dictionary<string, FacultyInfo> FacultyMap = new()
        {
            { "01", new FacultyInfo { Code = "01", Name = "AGRI", Domain = "agri.pstu.ac.bd", Table = "students_agri" } },
            { "02", new FacultyInfo { Code = "02", Name = "CSE", Domain = "cse.pstu.ac.bd", Table = "students_cse" } },
            { "03", new FacultyInfo { Code = "03", Name = "FBA", Domain = "fba.pstu.ac.bd", Table = "students_fba" } },
            { "04", new FacultyInfo { Code = "04", Name = "Fisheries", Domain = "fish.pstu.ac.bd", Table = "students_fish" } },
            { "05", new FacultyInfo { Code = "05", Name = "NFS", Domain = "nfs.pstu.ac.bd", Table = "students_nfs" } },
            { "06", new FacultyInfo { Code = "06", Name = "ESDM", Domain = "esdm.pstu.ac.bd", Table = "students_esdm" } }
        };

        public class EmailValidationResult
        {
            public bool Valid { get; set; }
            public string Error { get; set; }
            public FacultyInfo Faculty { get; set; }
        }

        public class FacultyInfo
        {
            public string Code { get; set; }
            public string Name { get; set; }
            public string Domain { get; set; }
            public string Table { get; set; }
        }

        public static EmailValidationResult ValidateStudentEmail(string email)
        {
            var pattern = @"^ug(\d{2})(\d{2})(\d{3})@([a-z]+)\.pstu\.ac\.bd$";
            var match = Regex.Match(email.ToLower(), pattern, RegexOptions.IgnoreCase);

            if (!match.Success)
            {
                return new EmailValidationResult
                {
                    Valid = false,
                    Error = "Invalid email format. Must be ugYYFFNNN@faculty.pstu.ac.bd (e.g., ug2201053@agri.pstu.ac.bd)"
                };
            }

            var year = match.Groups[1].Value;
            var facultyCode = match.Groups[2].Value;
            var studentNum = match.Groups[3].Value;
            var domain = match.Groups[4].Value;

            if (!FacultyMap.ContainsKey(facultyCode))
            {
                return new EmailValidationResult
                {
                    Valid = false,
                    Error = "Invalid faculty code. Must be 01-06"
                };
            }

            var faculty = FacultyMap[facultyCode];
            var expectedDomain = faculty.Domain.Split('.')[0];

            if (domain != expectedDomain)
            {
                return new EmailValidationResult
                {
                    Valid = false,
                    Error = $"Faculty code {facultyCode} does not match domain. Expected: ug{year}{facultyCode}{studentNum}@{faculty.Domain}"
                };
            }

            return new EmailValidationResult
            {
                Valid = true,
                Faculty = faculty
            };
        }
    }
}
