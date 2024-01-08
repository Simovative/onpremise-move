SET @newA5Url := 'local.academyfive.net' collate utf8_unicode_ci;
SET @oldA5Url := '' collate utf8_unicode_ci;
SET @oldA5UrlPrefix := '' collate utf8_unicode_ci;
SELECT SUBSTRING(
        s.`values`,
        LOCATE('"', s.`values`, (LOCATE('academy_url":', s.`values`) + CHAR_LENGTH('academy_url":'))) + 1,
        (LOCATE('"', s.`values`, LOCATE('"', s.`values`, (LOCATE('academy_url":', s.`values`) + CHAR_LENGTH('academy_url":'))) + 1)
            - (LOCATE('"', s.`values`, (LOCATE('academy_url":', s.`values`) + CHAR_LENGTH('academy_url":'))) + 1))
    ) as a5url,
    SUBSTRING(
        s.`values`,
        LOCATE('"academy_url":', s.`values`),
        (LOCATE('"', s.`values`, (LOCATE('"academy_url":', s.`values`) + CHAR_LENGTH('"academy_url":'))) + 1)
           - LOCATE('"academy_url":', s.`values`)
    ) as prefix
INTO @oldA5Url, @oldA5UrlPrefix
FROM settings s
WHERE s.module = 'application'
        AND s.`values` LIKE '%academy_url%'
        AND s.`values` NOT LIKE '%academy_url":""%'
LIMIT 1;
SELECT @oldA5Url;
SELECT @oldA5UrlPrefix;

UPDATE settings s
SET `s`.`values` = REPLACE(`s`.`values`, CONCAT(@oldA5UrlPrefix, @oldA5Url, '"'), CONCAT(@oldA5UrlPrefix, @newA5Url, '"'))
WHERE `s`.`module` = 'application'
    AND `s`.`values` LIKE '%academy_url%'
    AND s.`values` NOT LIKE '%academy_url":""%';
UPDATE settings s
SET `s`.`values` = REPLACE(`s`.`values`, '"academy_url":""', CONCAT(@oldA5UrlPrefix, @newA5Url, '"'))
WHERE `s`.`module` = 'application'
    AND `s`.`values` LIKE '%academy_url":""%';
UPDATE settings s
SET `s`.`values` = REPLACE(`s`.`values`, '"academy_url": ""', CONCAT(@oldA5UrlPrefix, @newA5Url, '"'))
WHERE `s`.`module` = 'application'
    AND `s`.`values` LIKE '%academy_url": ""%';
