DELETE
FROM `cms_layout`
WHERE `cms_layout`.`domain` NOT IN (SELECT `domain_id` FROM `cms_community`);

-- delete areas for deleted layouts
DELETE
FROM `cms_area`
WHERE `cms_area`.`layout` NOT IN (SELECT `id` FROM `cms_layout`);

-- insert default layout for every application
INSERT INTO `cms_layout` (`domain`, `aktiv`, `name`, `typ`, `template`, `head`, `cssfile`)
SELECT `cms_domains`.`id`,
       1,
       'Ganze Seite',
       'xhtml',
       '<div id="page">
            <div id="header">
                <a href="" title="Logo">
                    <img src="img/header.jpg" alt="Logo"/>
                </a>
                <tpl_menu name="navi" root="1,home" levels="1" collapse="all" type="text">
                    <div class="clear"></div>
            </div>
            <div id="subHeader">
                <div id="crumbs">
                    <tpl_modul name="history">
                </div>
                <div id="loginInformation">
                    <tpl_modul name="login" anz_form="nein">
                        <div id="languageSwitch" style="display: inline-block; margin-left: 10px;">
                            <tpl_modul name="languageSwitch">
                        </div>
                </div>
            </div>
            <div style="clear: both"></div>
            <div id="center_full_page">
                <tpl_content area="main">
                    <div class="clear"></div>
            </div>
        </div>
        <tpl_modul name="templates" tp_ac="pageFooter">
            <script type="text/javascript">
                if (document.getElementById("maintab")) {
                    initializetabcontent("maintab");
                }
            </script>',
       '<script src="js/tabcontent.js" type="text/javascript"></script>
        <script langauge="javacript" type="text/javascript">
            var IE = false;
        </script>
        <!--[if lte IE 7]>
        <script langauge="javacript" type="text/javascript">
            IE = true;
        </script>
        <![endif]-->
        <script type="text/javascript" src="js/ufo.js"></script>
        <script type="text/javascript" src="js/functions.js"></script>
        <script type="text/javascript" src="jscripts/jquery/js/jquery-1.11.1.min.js"></script>
        <script type="text/javascript" src="js/jquery/plugins/jquery.ba-bbq.min.js"></script>
        <script type="text/javascript" src="js/jquery/plugins/jquery-ui_1.9.0.js"></script>
        <script src="js/jquery/plugins/jquery.tipsy.js" type="text/javascript"></script>
        <script src="js/jquery/plugins/jquery.simplemodal.1.4.4.min.js" type="text/javascript"></script>
        <script src="js/jquery/plugins/jquery.autoSuggest.js" type="text/javascript"></script>
        <script src="js/jquery/plugins/jquery.numeric.js" type="text/javascript"></script>
        <script type="text/javascript" src="js/message.js"></script>
        <script type="text/javascript" src="jscripts/classes/Core/Class.js"></script>
        <link type="text/css" rel="stylesheet" href="js/jquery/css/ui-lightness/jquery-ui-1.8.2.custom.css">',
       ''
FROM `cms_domains`
WHERE `cms_domains`.`id` NOT IN (SELECT `domain_id` FROM `cms_community`);

-- insert new area for new cms_layouts
INSERT INTO `cms_area` (`layout`, `name`, `shorttag`)
SELECT `cms_layout`.`id`, 'Standard', 'main'
FROM `cms_layout`
WHERE `cms_layout`.`domain` NOT IN (SELECT `domain_id` FROM `cms_community`);

-- update all cms_preview templates of applications to the layout for the domain
UPDATE `cms_preview`
    INNER JOIN `cms_layout`
        ON `cms_layout`.`domain` = `cms_preview`.`domain`
        AND `cms_layout`.`domain` NOT IN (SELECT `domain_id` FROM `cms_community`)
SET `cms_preview`.`template`=`cms_layout`.`id`;

-- update cms_container with new associated area
UPDATE `cms_container`
    INNER JOIN `cms_menue`
        ON `cms_container`.`pageid` = `cms_menue`.`id`
    INNER JOIN `cms_layout`
        ON `cms_layout`.`domain` = `cms_menue`.`domain`
        AND `cms_layout`.`domain` NOT IN (SELECT `domain_id` FROM `cms_community`)
    INNER JOIN `cms_area` 
        ON `cms_layout`.`id` = `cms_area`.`layout`
SET `cms_container`.`typ`=`cms_area`.`id`;
