param
(
    [Parameter(Mandatory)]
    [hashtable]$Target
)


pxDsc 'Registry(POL): HKLM:\SOFTWARE\Microsoft\wcmsvc\wifinetworkmanager\config\AutoConnectAllowedOEM' @{
    Target     = $Target
    Resource   = 'Registry'
    Module     = 'PSDscResources'
    Properties = @{
        ValueName = 'AutoConnectAllowedOEM'
        ValueData = @('0')
        ValueType = 'Dword'
        Key       = 'HKLM:\SOFTWARE\Microsoft\wcmsvc\wifinetworkmanager\config'
    }
}

pxDsc 'Registry(POL): HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoAutorun' @{
    Target     = $Target
    Resource   = 'Registry'
    Module     = 'PSDscResources'
    Properties = @{
        ValueName = 'NoAutorun'
        ValueData = @('1')
        ValueType = 'Dword'
        Key       = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    }
}

pxDsc 'Audit Credential Validation (Success) - Inclusion' @{
    Target     = $Target
    Resource   = 'AuditPolicySubcategory'
    Module     = 'AuditPolicyDSC'
    Properties = @{
        Name      = 'Credential Validation'
        Ensure    = 'Present'
        AuditFlag = 'Success'
    }
}

pxDsc 'Audit Credential Validation (Failure) - Inclusion' @{
    Target     = $Target
    Resource   = 'AuditPolicySubcategory'
    Module     = 'AuditPolicyDSC'
    Properties = @{
        Name      = 'Credential Validation'
        Ensure    = 'Present'
        AuditFlag = 'Failure'
    }
}

pxDsc 'UserRightsAssignment(INF): Impersonate_a_client_after_authentication' @{
    Target     = $Target
    Resource   = 'UserRightsAssignment'
    Module     = 'SecurityPolicyDSC'
    Properties = @{
        Policy   = 'Impersonate_a_client_after_authentication'
        Force    = $True
        Identity = @('*S-1-5-32-544', '*S-1-5-6')
    }
}

pxDsc 'UserRightsAssignment(INF): Take_ownership_of_files_or_other_objects' @{
    Target     = $Target
    Resource   = 'UserRightsAssignment'
    Module     = 'SecurityPolicyDSC'
    Properties = @{
        Policy   = 'Take_ownership_of_files_or_other_objects'
        Force    = $True
        Identity = @('*S-1-5-32-544')
    }
}

pxDsc 'SecurityRegistry(INF): Microsoft_network_client_Send_unencrypted_password_to_third_party_SMB_servers' @{
    Target     = $Target
    Resource   = 'SecurityOption'
    Module     = 'SecurityPolicyDSC'
    Properties = @{
        Name                                                                          = 'Microsoft_network_client_Send_unencrypted_password_to_third_party_SMB_servers'
        Microsoft_network_client_Send_unencrypted_password_to_third_party_SMB_servers = 'Disabled'
    }
}

pxDsc 'SecurityRegistry(INF): Accounts_Block_Microsoft_accounts' @{
    Target     = $Target
    Resource   = 'SecurityOption'
    Module     = 'SecurityPolicyDSC'
    Properties = @{
        Accounts_Block_Microsoft_accounts = 'Users cant add or log on with Microsoft accounts'
        Name                              = 'Accounts_Block_Microsoft_accounts'
    }
}

pxDsc 'LogonMessage' @{
    Target     = $Target
    Resource   = 'SecurityOption'
    Module     = 'SecurityPolicyDSC'
    Properties = @{
        Name                                                          = "Message Test"
        Interactive_logon_Message_text_for_users_attempting_to_log_on = 'Go6o'
    }
}

pxDsc 'SecuritySetting(INF): Multiple staff' @{
    Target     = $Target
    Resource   = 'AccountPolicy'
    Module     = 'SecurityPolicyDSC'
    Properties = @{
        Name                                = 'Multiple staff'
        Account_lockout_threshold           = 11
        Account_lockout_duration            = 15
        Reset_account_lockout_counter_after = 15
    }
}

pxDsc 'SecurityRegistry(INF): Interactive_logon_Do_not_require_CTRL_ALT_DEL' @{
    Target     = $Target
    Resource   = 'SecurityOption'
    Module     = 'SecurityPolicyDSC'
    Properties = @{
        Name                                          = 'Interactive_logon_Do_not_require_CTRL_ALT_DEL'
        Interactive_logon_Do_not_require_CTRL_ALT_DEL = 'Disabled'
    }
}

pxDsc 'SecurityRegistry(INF): User_Account_Control_Run_all_administrators_in_Admin_Approval_Mode' @{
    Target     = $Target
    Resource   = 'SecurityOption'
    Module     = 'SecurityPolicyDSC'
    Properties = @{
        Name                                                               = 'User_Account_Control_Run_all_administrators_in_Admin_Approval_Mode'
        User_Account_Control_Run_all_administrators_in_Admin_Approval_Mode = 'Enabled'
    }
}

pxDsc 'ActivateClientSideExtension' @{
    Target     = $Target
    Resource   = 'RefreshRegistryPolicy'
    Module     = 'GPRegistryPolicyDsc'
    Properties = @{
        IsSingleInstance = 'Yes'
    }
}