-- Insert extracted vaccination data for Max from immunization_page_001.png
-- Target: tempdb on localhost (Windows Authentication)

USE tempdb;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Store IDs for foreign key relationships
DECLARE @OwnerId INT;
DECLARE @PetId INT;
DECLARE @VeterinarianId INT;

-- =============================================================================
-- Insert Owner (John Smith)
-- =============================================================================
INSERT INTO dbo.Owners (FirstName, LastName, StreetAddress, City, State, ZipCode)
VALUES ('John', 'Smith', '123 Oak Street', 'Springfield', 'IL', '62701');

SET @OwnerId = SCOPE_IDENTITY();
PRINT 'Owner inserted: OwnerId = ' + CAST(@OwnerId AS NVARCHAR(10));

-- =============================================================================
-- Insert Veterinarian (Dr. Sarah Johnson)
-- =============================================================================
INSERT INTO dbo.Veterinarians (FirstName, LastName, ClinicName)
VALUES ('Sarah', 'Johnson', 'Sunny Valley Animal Hospital');

SET @VeterinarianId = SCOPE_IDENTITY();
PRINT 'Veterinarian inserted: VeterinarianId = ' + CAST(@VeterinarianId AS NVARCHAR(10));

-- =============================================================================
-- Insert Pet (Max - Labrador Retriever)
-- =============================================================================
INSERT INTO dbo.Pets (OwnerId, PetName, Species, Breed, Color, Gender, DateOfBirth)
VALUES (@OwnerId, 'Max', 'Dog', 'Labrador Retriever', 'Yellow', 'M', '2019-02-25');

SET @PetId = SCOPE_IDENTITY();
PRINT 'Pet inserted: PetId = ' + CAST(@PetId AS NVARCHAR(10));

-- =============================================================================
-- Insert Vaccination Records
-- =============================================================================

-- DHPP: 02/15/2023 (expires 02/15/2024)
INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, ExpirationDate, DoseNumber, Notes)
SELECT @PetId, VaccineId, @VeterinarianId, '2023-02-15', '2024-02-15', 1, 'Routine vaccination'
FROM dbo.Vaccines WHERE VaccineCode = 'DHPP';

-- Rabies: 02/15/2023 (expires 02/15/2026 - 3 year vaccine)
INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, ExpirationDate, DoseNumber, Notes)
SELECT @PetId, VaccineId, @VeterinarianId, '2023-02-15', '2026-02-15', 1, '3-year rabies vaccine'
FROM dbo.Vaccines WHERE VaccineCode = 'RABI';

-- Bordetella: 03/20/2023 (expires 03/20/2024 - kennel cough)
INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, ExpirationDate, DoseNumber, Notes)
SELECT @PetId, VaccineId, @VeterinarianId, '2023-03-20', '2024-03-20', 1, 'Kennel cough vaccine'
FROM dbo.Vaccines WHERE VaccineCode = 'BORD';

-- DHPP Booster: 02/15/2024 (expires 02/15/2025)
INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, ExpirationDate, DoseNumber, Notes)
SELECT @PetId, VaccineId, @VeterinarianId, '2024-02-15', '2025-02-15', 2, 'Annual booster'
FROM dbo.Vaccines WHERE VaccineCode = 'DHPP';

-- Rabies Booster: 02/15/2024 (expires 02/15/2027 - 3 year vaccine)
INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, ExpirationDate, DoseNumber, Notes)
SELECT @PetId, VaccineId, @VeterinarianId, '2024-02-15', '2027-02-15', 2, '3-year rabies booster'
FROM dbo.Vaccines WHERE VaccineCode = 'RABI';

-- Bordetella Booster: 03/20/2024 (expires 03/20/2025)
INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, ExpirationDate, DoseNumber, Notes)
SELECT @PetId, VaccineId, @VeterinarianId, '2024-03-20', '2025-03-20', 2, 'Annual booster'
FROM dbo.Vaccines WHERE VaccineCode = 'BORD';

-- Leptospirosis: 02/15/2023 (expires 02/15/2024 - included in DHPP)
INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, ExpirationDate, DoseNumber, Notes)
SELECT @PetId, VaccineId, @VeterinarianId, '2023-02-15', '2024-02-15', 1, 'Included in DHPP'
FROM dbo.Vaccines WHERE VaccineCode = 'LEPT';

-- Leptospirosis Booster: 02/15/2024 (expires 02/15/2025)
INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, ExpirationDate, DoseNumber, Notes)
SELECT @PetId, VaccineId, @VeterinarianId, '2024-02-15', '2025-02-15', 2, 'Annual booster'
FROM dbo.Vaccines WHERE VaccineCode = 'LEPT';

PRINT '';
PRINT 'All vaccination records inserted successfully!';
GO

-- =============================================================================
-- Verification: Display all inserted data
-- =============================================================================
PRINT '';
PRINT '=== VERIFICATION QUERY ===';
PRINT '';

PRINT 'OWNER INFORMATION:';
SELECT OwnerId, FirstName, LastName, StreetAddress, City, State, ZipCode
FROM dbo.Owners
WHERE FirstName = 'John' AND LastName = 'Smith';

PRINT '';
PRINT 'VETERINARIAN INFORMATION:';
SELECT VeterinarianId, FirstName, LastName, ClinicName
FROM dbo.Veterinarians
WHERE FirstName = 'Sarah' AND LastName = 'Johnson';

PRINT '';
PRINT 'PET INFORMATION:';
SELECT p.PetId, p.PetName, p.Species, p.Breed, p.Color, p.Gender, p.DateOfBirth, o.FirstName + ' ' + o.LastName AS Owner
FROM dbo.Pets p
JOIN dbo.Owners o ON p.OwnerId = o.OwnerId
WHERE p.PetName = 'Max';

PRINT '';
PRINT 'VACCINATION RECORDS:';
SELECT
    vr.RecordId,
    v.VaccineName,
    vr.AdministrationDate,
    vr.ExpirationDate,
    vr.DoseNumber,
    vr.Notes,
    vet.FirstName + ' ' + vet.LastName AS Veterinarian
FROM dbo.VaccinationRecords vr
JOIN dbo.Vaccines v ON vr.VaccineId = v.VaccineId
LEFT JOIN dbo.Veterinarians vet ON vr.VeterinarianId = vet.VeterinarianId
WHERE vr.PetId = (SELECT PetId FROM dbo.Pets WHERE PetName = 'Max')
ORDER BY vr.AdministrationDate, v.VaccineName;

PRINT '';
PRINT 'SUMMARY:';
SELECT 'Owners' AS TableName, COUNT(*) AS RecordCount FROM dbo.Owners
UNION ALL
SELECT 'Pets', COUNT(*) FROM dbo.Pets
UNION ALL
SELECT 'Veterinarians', COUNT(*) FROM dbo.Veterinarians
UNION ALL
SELECT 'VaccinationRecords', COUNT(*) FROM dbo.VaccinationRecords;
GO
