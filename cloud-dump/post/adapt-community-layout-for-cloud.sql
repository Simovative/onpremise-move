-- delete content that is currently on a not used layout
DELETE cc
FROM cms_container cc
INNER JOIN cms_preview cp
    ON cp.id = cc.pageid
    AND cc.lang = cp.lang
INNER JOIN cms_area `ca`
    ON `ca`.id = cc.typ
WHERE `ca`.layout != cp.template;

-- delete community layouts
DELETE
FROM `cms_layout`
WHERE `cms_layout`.`domain` IN (SELECT `domain_id` FROM `cms_community`);

-- delete areas for deleted layouts
DELETE
FROM `cms_area`
WHERE `cms_area`.`layout` NOT IN (SELECT `id` FROM `cms_layout`);

-- insert default layout for every community
INSERT INTO `cms_layout` (`domain`, `aktiv`, `name`, `typ`, `template`, `head`, `cssfile`)
SELECT `cms_domains`.`id`,
       1,
       'Community-Fullpage',
       '',
       '<tpl_modul name="templates" tp_ac="pageBase" layout="fullpage">',
       '',
       ''
FROM `cms_domains`
WHERE `cms_domains`.`id` IN (SELECT `domain_id` FROM `cms_community`);

-- insert new area for new cms_layouts
INSERT INTO `cms_area` (`layout`, `name`, `shorttag`)
SELECT `cms_layout`.`id`, 'Standard', 'main'
FROM `cms_layout`
WHERE `cms_layout`.`domain` IN (SELECT `domain_id` FROM `cms_community`);

-- update all cms_preview templates of communities to the layout for the domain
UPDATE `cms_preview`
    INNER JOIN `cms_layout`
    ON `cms_layout`.`domain` = `cms_preview`.`domain`
        AND `cms_layout`.`domain` IN (SELECT `domain_id` FROM `cms_community`)
SET `cms_preview`.`template`=`cms_layout`.`id`;

-- update cms_container with new associated area
UPDATE `cms_container`
    INNER JOIN `cms_menue`
    ON `cms_container`.`pageid` = `cms_menue`.`id`
    INNER JOIN `cms_layout`
    ON `cms_layout`.`domain` = `cms_menue`.`domain`
        AND `cms_layout`.`domain` IN (SELECT `domain_id` FROM `cms_community`)
    INNER JOIN `cms_area` ON `cms_layout`.`id` = `cms_area`.`layout`
SET `cms_container`.`typ`=`cms_area`.`id`;
