-- Pet Vaccination Database Schema
-- Target: tempdb on localhost (Windows Authentication)
-- Normalized design with proper constraints and indexing

USE tempdb;
GO

-- Drop existing tables if they exist (in reverse dependency order)
IF OBJECT_ID('dbo.VaccinationRecords', 'U') IS NOT NULL DROP TABLE dbo.VaccinationRecords;
IF OBJECT_ID('dbo.Pets', 'U') IS NOT NULL DROP TABLE dbo.Pets;
IF OBJECT_ID('dbo.Owners', 'U') IS NOT NULL DROP TABLE dbo.Owners;
IF OBJECT_ID('dbo.Veterinarians', 'U') IS NOT NULL DROP TABLE dbo.Veterinarians;
IF OBJECT_ID('dbo.Vaccines', 'U') IS NOT NULL DROP TABLE dbo.Vaccines;
GO

-- =============================================================================
-- Table: Owners
-- Description: Pet owner contact information
-- =============================================================================
CREATE TABLE dbo.Owners (
    OwnerId         INT IDENTITY(1,1) NOT NULL,
    FirstName       NVARCHAR(50)      NOT NULL,
    LastName        NVARCHAR(50)      NOT NULL,
    StreetAddress   NVARCHAR(200)     NULL,
    City            NVARCHAR(100)     NULL,
    State           NVARCHAR(50)      NULL,
    ZipCode         VARCHAR(10)       NULL,
    Phone           VARCHAR(20)       NULL,
    Email           NVARCHAR(255)     NULL,
    CreatedDate     DATETIME2         NOT NULL DEFAULT GETDATE(),
    ModifiedDate    DATETIME2         NULL,

    CONSTRAINT PK_Owners PRIMARY KEY CLUSTERED (OwnerId),
    CONSTRAINT CK_Owners_Email CHECK (Email IS NULL OR Email LIKE '%_@_%.__%')
);
GO

-- Index for searching owners by name
CREATE NONCLUSTERED INDEX IX_Owners_Name
    ON dbo.Owners (LastName, FirstName);
GO

-- =============================================================================
-- Table: Pets
-- Description: Pet information with foreign key to owner
-- =============================================================================
CREATE TABLE dbo.Pets (
    PetId           INT IDENTITY(1,1) NOT NULL,
    OwnerId         INT               NOT NULL,
    PetName         NVARCHAR(100)     NOT NULL,
    Species         VARCHAR(50)       NOT NULL DEFAULT 'Dog',
    Breed           NVARCHAR(100)     NULL,
    Color           NVARCHAR(50)      NULL,
    Gender          CHAR(1)           NULL,
    DateOfBirth     DATE              NULL,
    MicrochipNumber VARCHAR(50)       NULL,
    IsActive        BIT               NOT NULL DEFAULT 1,
    CreatedDate     DATETIME2         NOT NULL DEFAULT GETDATE(),
    ModifiedDate    DATETIME2         NULL,

    CONSTRAINT PK_Pets PRIMARY KEY CLUSTERED (PetId),
    CONSTRAINT FK_Pets_Owners FOREIGN KEY (OwnerId)
        REFERENCES dbo.Owners (OwnerId) ON DELETE CASCADE,
    CONSTRAINT CK_Pets_Gender CHECK (Gender IS NULL OR Gender IN ('M', 'F')),
    CONSTRAINT CK_Pets_Species CHECK (Species IN ('Dog', 'Cat', 'Bird', 'Rabbit', 'Other'))
);
GO

-- Index for searching pets by owner
CREATE NONCLUSTERED INDEX IX_Pets_OwnerId
    ON dbo.Pets (OwnerId)
    INCLUDE (PetName, Species, Breed);
GO

-- Index for searching pets by name
CREATE NONCLUSTERED INDEX IX_Pets_Name
    ON dbo.Pets (PetName);
GO

-- =============================================================================
-- Table: Vaccines
-- Description: Reference table for vaccine types
-- =============================================================================
CREATE TABLE dbo.Vaccines (
    VaccineId           INT IDENTITY(1,1) NOT NULL,
    VaccineName         NVARCHAR(100)     NOT NULL,
    VaccineCode         VARCHAR(20)       NOT NULL,
    Description         NVARCHAR(500)     NULL,
    ApplicableSpecies   VARCHAR(50)       NOT NULL DEFAULT 'Dog',
    RecommendedInterval INT               NULL,  -- Days between doses
    IsActive            BIT               NOT NULL DEFAULT 1,

    CONSTRAINT PK_Vaccines PRIMARY KEY CLUSTERED (VaccineId),
    CONSTRAINT UQ_Vaccines_Code UNIQUE (VaccineCode)
);
GO

-- =============================================================================
-- Table: Veterinarians
-- Description: Veterinarian information
-- =============================================================================
CREATE TABLE dbo.Veterinarians (
    VeterinarianId  INT IDENTITY(1,1) NOT NULL,
    FirstName       NVARCHAR(50)      NOT NULL,
    LastName        NVARCHAR(50)      NOT NULL,
    LicenseNumber   VARCHAR(50)       NULL,
    ClinicName      NVARCHAR(200)     NULL,
    Phone           VARCHAR(20)       NULL,
    Email           NVARCHAR(255)     NULL,
    IsActive        BIT               NOT NULL DEFAULT 1,

    CONSTRAINT PK_Veterinarians PRIMARY KEY CLUSTERED (VeterinarianId)
);
GO

-- Index for searching veterinarians by name
CREATE NONCLUSTERED INDEX IX_Veterinarians_Name
    ON dbo.Veterinarians (LastName, FirstName);
GO

-- =============================================================================
-- Table: VaccinationRecords
-- Description: Records of administered vaccinations (junction table)
-- =============================================================================
CREATE TABLE dbo.VaccinationRecords (
    RecordId            INT IDENTITY(1,1) NOT NULL,
    PetId               INT               NOT NULL,
    VaccineId           INT               NOT NULL,
    VeterinarianId      INT               NULL,
    AdministrationDate  DATE              NOT NULL,
    ExpirationDate      DATE              NULL,
    DoseNumber          TINYINT           NULL DEFAULT 1,
    LotNumber           VARCHAR(50)       NULL,
    Notes               NVARCHAR(500)     NULL,
    CreatedDate         DATETIME2         NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_VaccinationRecords PRIMARY KEY CLUSTERED (RecordId),
    CONSTRAINT FK_VaccinationRecords_Pets FOREIGN KEY (PetId)
        REFERENCES dbo.Pets (PetId) ON DELETE CASCADE,
    CONSTRAINT FK_VaccinationRecords_Vaccines FOREIGN KEY (VaccineId)
        REFERENCES dbo.Vaccines (VaccineId),
    CONSTRAINT FK_VaccinationRecords_Veterinarians FOREIGN KEY (VeterinarianId)
        REFERENCES dbo.Veterinarians (VeterinarianId),
    CONSTRAINT CK_VaccinationRecords_Dates CHECK (ExpirationDate IS NULL OR ExpirationDate > AdministrationDate)
);
GO

-- Index for querying vaccination history by pet
CREATE NONCLUSTERED INDEX IX_VaccinationRecords_PetId
    ON dbo.VaccinationRecords (PetId, AdministrationDate DESC)
    INCLUDE (VaccineId, VeterinarianId);
GO

-- Index for finding pets due for vaccinations
CREATE NONCLUSTERED INDEX IX_VaccinationRecords_Expiration
    ON dbo.VaccinationRecords (ExpirationDate)
    WHERE ExpirationDate IS NOT NULL;
GO

-- =============================================================================
-- Insert reference data for common dog vaccines
-- =============================================================================
INSERT INTO dbo.Vaccines (VaccineName, VaccineCode, Description, ApplicableSpecies, RecommendedInterval)
VALUES
    ('Distemper', 'DIST', 'Canine distemper virus vaccine', 'Dog', 365),
    ('Measles', 'MEAS', 'Measles vaccine for puppies', 'Dog', NULL),
    ('Parainfluenza', 'PARA', 'Canine parainfluenza virus vaccine', 'Dog', 365),
    ('DHPP', 'DHPP', 'Distemper, Hepatitis, Parainfluenza, Parvovirus combination', 'Dog', 365),
    ('Bordetella', 'BORD', 'Kennel cough vaccine', 'Dog', 180),
    ('Coronavirus', 'CORO', 'Canine coronavirus vaccine', 'Dog', 365),
    ('Leptospirosis', 'LEPT', 'Leptospirosis vaccine', 'Dog', 365),
    ('Lyme Disease', 'LYME', 'Borrelia burgdorferi vaccine', 'Dog', 365),
    ('Rabies', 'RABI', 'Rabies virus vaccine (legally required)', 'Dog', 1095);
GO

-- =============================================================================
-- Insert sample data from the vaccination record
-- =============================================================================

-- Insert owner
INSERT INTO dbo.Owners (FirstName, LastName, StreetAddress, City, State, ZipCode)
VALUES ('Jane', 'Doe', '1575 McDonald Street', 'Mount Pleasant', 'TX', '38474');

-- Insert veterinarian
INSERT INTO dbo.Veterinarians (FirstName, LastName, ClinicName)
VALUES ('John', 'Smith', NULL);

-- Insert pet
INSERT INTO dbo.Pets (OwnerId, PetName, Species, Breed, Color, Gender, DateOfBirth)
VALUES (1, 'Chewy', 'Dog', 'Labrador', 'Brown', 'M', '2014-02-25');

-- Insert vaccination records from the document
DECLARE @PetId INT = 1;
DECLARE @VetId INT = 1;

INSERT INTO dbo.VaccinationRecords (PetId, VaccineId, VeterinarianId, AdministrationDate, DoseNumber)
VALUES
    -- Distemper: 02/01/2014
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'DIST'), @VetId, '2014-02-01', 1),
    -- Measles: 02/01/2015
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'MEAS'), @VetId, '2015-02-01', 1),
    -- Parainfluenza: 02/01/2014
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'PARA'), @VetId, '2014-02-01', 1),
    -- DHPP: 02/01/2016, 08/01/2017, 08/01/2018
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'DHPP'), @VetId, '2016-02-01', 1),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'DHPP'), @VetId, '2017-08-01', 2),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'DHPP'), @VetId, '2018-08-01', 3),
    -- Bordetella: 02/01/2016, 08/01/2017, 08/01/2018
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'BORD'), @VetId, '2016-02-01', 1),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'BORD'), @VetId, '2017-08-01', 2),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'BORD'), @VetId, '2018-08-01', 3),
    -- Coronavirus: 02/01/2016, 08/01/2017, 08/01/2018
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'CORO'), @VetId, '2016-02-01', 1),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'CORO'), @VetId, '2017-08-01', 2),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'CORO'), @VetId, '2018-08-01', 3),
    -- Leptospirosis: 02/01/2016, 08/01/2017, 08/01/2018
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'LEPT'), @VetId, '2016-02-01', 1),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'LEPT'), @VetId, '2017-08-01', 2),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'LEPT'), @VetId, '2018-08-01', 3),
    -- Lyme Disease: 02/01/2016, 08/01/2017
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'LYME'), @VetId, '2016-02-01', 1),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'LYME'), @VetId, '2017-08-01', 2),
    -- Rabies: 02/01/2016, 08/01/2018
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'RABI'), @VetId, '2016-02-01', 1),
    (@PetId, (SELECT VaccineId FROM dbo.Vaccines WHERE VaccineCode = 'RABI'), @VetId, '2018-08-01', 2);
GO

-- =============================================================================
-- Verification queries
-- =============================================================================
PRINT 'Schema created successfully. Running verification...';
PRINT '';

SELECT 'Owners' AS TableName, COUNT(*) AS RecordCount FROM dbo.Owners
UNION ALL
SELECT 'Pets', COUNT(*) FROM dbo.Pets
UNION ALL
SELECT 'Vaccines', COUNT(*) FROM dbo.Vaccines
UNION ALL
SELECT 'Veterinarians', COUNT(*) FROM dbo.Veterinarians
UNION ALL
SELECT 'VaccinationRecords', COUNT(*) FROM dbo.VaccinationRecords;
GO
