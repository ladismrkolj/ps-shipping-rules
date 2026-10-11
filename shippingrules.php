<?php

if (!defined('_PS_VERSION_')) {
    exit;
}

require_once __DIR__ . '/vendor/autoload.php';

class ShippingRules extends Module
{
    public function __construct()
    {
        $this->name = 'shippingrules';
        $this->tab = 'shipping_logistics';
        $this->version = '0.1.0';
        $this->author = 'Ladi Smrkolj';
        $this->need_instance = 0;
        $this->bootstrap = true;
        $this->ps_versions_compliancy = ['min' => '9.0.0', 'max' => '9.99.99'];
        parent::__construct();
        $this->displayName = $this->l('Shipping Rules');
        $this->description = $this->l('Shipping classes, rate tables and packing rules on top of native carriers.');
    }
}
