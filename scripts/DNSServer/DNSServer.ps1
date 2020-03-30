Configuration DNSServer {

    param ([string]$MachineName)

    Node $MachineName {

        WindowsFeature DnsServer {
            Ensure = 'Present'
            Name = 'DNS'
        }

        WindowsFeature DnsManagementTools {
            Ensure = 'Present'
            Name = 'RSAT-DNS-Server'
        }
    }
}