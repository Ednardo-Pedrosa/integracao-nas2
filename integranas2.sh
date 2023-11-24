#!/bin/bash

#clear
Menu() {
clear
#echo -e '\n'
echo "SCRIPT PARA INTEGRAO DE CONCENTRADORES"
echo ""
echo "Selecione a opcao desejada:"
echo ""
echo "[ 1 ] | Mikrotik"
echo "[ 2 ] | Huawei"
echo "[ 3 ] | Cisco"
echo "[ 4 ] | Accel-PPP"
echo "[ 5 ] | Juniper"
read opcao
case $opcao in
1) Mikrotik ;;
2) Huawei ;;
3) Cisco ;;
4) Accel ;;
5) Juniper ;;
0) Sair ;;
*) "Comando desconhecido"; echo ; Menu;;
#break ;;
esac
}

Mikrotik () {
clear
echo "Script - Integrao Mikrotik"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do Provedor:"
read PROVEDOR
echo "Usuario VPN:"
read USERVPN
echo "Senha NAS/VPN:"
read PASSVPNUSER
echo "IP do Radius:"
read RADIUS
echo "Porta do authentication:"
read AUC
echo "Porta do accounting:"
read ACC
echo "Porta de Aviso:"
read AVS
echo "Porta de Bloqueio:"
read BLQ
echo "Token:"
read TOKENAQUI
echo "Link do SGP:"
read LINKDOSGP
echo "IP do SGP:"
read IPSGP
echo "IP do NAS:"
read NAS
echo "Porta API:"
read PORTAPI
echo "Comunidade SNMP:"
read SNMP

cat <<EOF > Mikrotik-$PROVEDOR.txt

#PERFIL DE INTEGRAÇÃO MIKROTIK

:global USERVPN "$USERVPN"
:global AUC "$AUC"
:global ACC "$ACC"
:global AVS "$AVS"
:global BLQ "$BLQ"
:global PASSVPNUSER "$PASSVPNUSER"
:global RADIUS "$RADIUS"
:global TOKEN "$TOKENAQUI"
:global LINKDOSGP "$LINKDOSGP"
:global IPSGP "$IPSGP"
:global NAS "$NAS"
:global PORTAPI "$PORTAPI"
:global SNMP "$SNMP"
:global PROVEDOR "$PROVEDOR"

#GERANDO BACKUP DO CONCENTRADOR MIKROTIK:

/system backup save name=BACKUP_REALIZADO_ANTERIOR_INTEGRACAO_SGP
/export file=BACKUP_REALIZADO_ANTERIOR_INTEGRACAO_SGP_TXT

#REALZANDO AJUSTES DE CONFIGURACOES DO MIKROTIK:

/system ntp client set enabled=yes primary-ntp=200.160.0.8
/system clock set time-zone-name=America/Recife

#HABILITANDO O RADIUS E ACESSO API:

/radius incoming set accept=yes
/ip service set api disabled=no port=$PORTAPI address="$RADIUS,$IPSGP"
/user aaa set use-radius=yes
/ppp aaa set interim-update=5m use-radius=yes

#CONFIGURACAO SNMP:

/snmp community add addresses="$RADIUS,$IPSGP" name=$SNMP
/snmp set enabled=yes trap-community=$SNMP trap-version=2
/ppp secret set service=any [find .id!=999]

#CONFIGURACAO DE USUARIO SGP:

/user add name=SGP comment="SISTEMA SGP - COMUNICACAO API PORTA $PORTAPI - NAO REMOVER OU EDITAR" \
    group=full password=$PASSVPNUSER
/system logging set 0 action=memory disabled=no prefix="" topics=info,!account

#CONFIGURACAO RADIUS:

/radius
add comment="RADIUS SGP $PROVEDOR" secret=sgp@radius service=ppp,dhcp,login address=$RADIUS accounting-port=$ACC \
    authentication-port=$AUC timeout=00:00:03 src-address=$NAS

#CONFIGURACAO VPN:

/ppp profile add name="VPN-SGP-$PROVEDOR" use-encryption=yes
/interface  l2tp-client add connect-to=$IPSGP user=$USERVPN password=$PASSVPNUSER name="SGP-L2TP"\
    disabled=no profile="VPN-SGP-$PROVEDOR" comment="SGP-L2TP-$PROVEDOR" keepalive-timeout=30

#CONFIGURACAO ADDRESS-LIST E REGRAS DE FIREWALL - BLOQUEIO E REDIRECIONAMENTO PARA PAGINAS DE AVISO/BLOQUEIO

/ip firewall address-list 
add address=$RADIUS list=SITES-LIBERADOS
add address=$IPSGP list=SITES-LIBERADOS
add address=208.67.222.222 list=SITES-LIBERADOS
add address=208.67.222.220 list=SITES-LIBERADOS
add address=8.8.8.8 list=SITES-LIBERADOS
add address=8.8.4.4 list=SITES-LIBERADOS
add address=1.1.1.1 list=SITES-LIBERADOS
add address=10.24.0.0/22 list=BLOQUEADOS

/ip firewall filter
add chain=forward connection-mark=BLOQUEIO-AVISAR action=add-src-to-address-list \
    address-list=BLOQUEIO-AVISADOS address-list-timeout=00:01:00 comment="SGP REGRAS" dst-address=$IPSGP \
    dst-port=$AVS protocol=tcp
/ip firewall nat
add action=masquerade chain=srcnat comment="SGP REGRAS" dst-address-list=\
    SITES-LIBERADOS src-address-list=BLOQUEADOS
add action=dst-nat chain=dstnat comment="SGP REGRAS" dst-address-list=\
    !SITES-LIBERADOS dst-port=80,443 log-prefix="" protocol=tcp \
    src-address-list=BLOQUEADOS to-addresses=$IPSGP to-ports=$BLQ 
add action=dst-nat chain=dstnat comment="SGP REGRAS" connection-mark=\
    BLOQUEIO-AVISAR log-prefix="" protocol=tcp to-addresses=$IPSGP to-ports=$AVS
/ip firewall mangle
add chain=prerouting connection-state=new src-address-list=BLOQUEIO-AVISAR protocol=tcp dst-port=80,443 \
    action=mark-connection new-connection-mark=BLOQUEIO-VERIFICAR passthrough=yes comment="SGP REGRAS" 
add chain=prerouting connection-mark=BLOQUEIO-VERIFICAR src-address-list=!BLOQUEIO-AVISADOS \
    action=mark-connection new-connection-mark=BLOQUEIO-AVISAR comment="SGP REGRAS" 
/ip firewall raw
add action=notrack chain=output comment="SGP REGRAS - EVITA NAT PARA O IP DO RADIUS $RADIUS" \
    dst-address=$RADIUS dst-port="$AUC-$ACC,3799" protocol=udp
add action=drop chain=prerouting comment="SGP BLOQUEIO" dst-address-list=\
    !SITES-LIBERADOS src-address-list=BLOQUEADOS
/system scheduler
add interval=4h name=sgp-aviso on-event=sgp-aviso policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive start-time=01:00:00 disabled=yes
/system script
add name=sgp-aviso policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive source=":log info\
    \_\"sgp aviso\";\r\
    \n/file remove [find where name=sgp_aviso.rsc]\r\
    \n/tool fetch url=\"$LINKDOSGP/ws/mikrotik/aviso/pendencia/\\?token=$TOKEN&app=mikrotik\" dst-path=sgp_aviso.rsc;\r\
    \n:delay 30s\r\
    \nimport file-name=sgp_aviso.rsc;\r\
    \n:delay 10s;\r\
    \n/ip firewall address-list set timeout=00:15:00 [/ip firewall address-list find list=BLOQUEIO-AVISAR]";\

#CHECANDO CONFIGURACOES IPV6 - CONFIGURACAO COLETA PDV6 E BLOQUEIOV6:

:global versao [/system package get number=0 version ]; :global versao2 [:pick $versao 0 [:find "$versao" "." -3]];
:delay 2s
:put $versao2
:if ($versao2=7) do={
    :global ipv6 [/ipv6 settings get disable-ipv6]
    :if ($ipv6=false) do={
    :log info "############\nSERVICO IPV6 HABILITADO NO EQUIPAMENTO\n############"
    :log info "CONFIGURANDO O POOL DE BLOQUEIO IPv6"
    /ipv6 pool add name=bloqueiov6pd prefix-length=64 prefix=2001:DB9:100::/40
    /ipv6 pool add name=bloqueiov6prefix prefix-length=64 prefix=2001:DBA:900::/40
    :log info "CONFIGURANDO O SCRIPT NOS PROFILE DOS PPPOE SERVER"
    /ppp profile set  on-up=":local \
        ipv6pool \"bloqueiov6pd\"\r\
        \n:local prefixo\r\
        \n:local servername \"<pppoe-\$user>\"\r\
        \n:delay 30s\r\
        \n:log info [/ipv6 dhcp-server binding find server=\"\$servername\"]\r\
        \n:foreach binding in=[/ipv6 dhcp-server binding find status=\"bound\" server=\"\$servername\"] do={\r\
        \n:set prefixo [/ipv6 dhcp-server binding get \$binding address]\r\
        \n:log info \"FETCH $LINKDOSGP/ws/radius/ipv6/update/\\\?token=$TOKEN&username=\$user&app=mikrotik&nas\
        ip=\$NAS&pd=\$prefixo\"\r\
        \n/tool fetch url=\"$LINKDOSGP/ws/radius/ipv6/update/\\\?token=$TOKEN&username=\$user&app=mikrotik&nasip=\$NAS&\
        pd=\$prefixo\" mode=http as-value output=user\r\
        \n}" [find .id!=999]
    /ppp profile set on-down=":local servernam\
        e \"<pppoe-\$user>\"\r\
        \n/ipv6 dhcp-server binding remove [find server=\$servername]\r\
        \n:local servername \"<pppoe-\$user>\"\r\
        \n/ipv6 dhcp-server remove [find numbers=\$user]\r\
        \n" [find .id!=999]
    } else={
        :log info "############\nSERVICO IPV6 DESATIVADO NO EQUIPAMENTO\n############"
    }
} else={
    :if ($versao2=6) do={
    :global ipv6 [/system package get ipv6 disabled ]
    :if ($ipv6=false) do={
    :log info "############\nSERVICO IPV6 HABILITADO NO EQUIPAMENTO\n############"
    :log info "CONFIGURANDO O POOL DE BLOQUEIO IPv6"
    /ipv6 pool add name=bloqueiov6pd prefix-length=64 prefix=2001:DB9:100::/40
    /ipv6 pool add name=bloqueiov6prefix prefix-length=64 prefix=2001:DBA:900::/40
    :log info "CONFIGURANDO O SCRIPT NOS PROFILE DOS PPPOE SERVER"
    /ppp profile set  on-up=":local \
        ipv6pool \"bloqueiov6pd\"\r\
        \n:local prefixo\r\
        \n:local servername \"<pppoe-\$user>\"\r\
        \n:delay 30s\r\
        \n:log info [/ipv6 dhcp-server binding find server=\"\$servername\"]\r\
        \n:foreach binding in=[/ipv6 dhcp-server binding find status=\"bound\" server=\"\$servername\"] do={\r\
        \n:set prefixo [/ipv6 dhcp-server binding get \$binding address]\r\
        \n:log info \"FETCH $LINKDOSGP/ws/radius/ipv6/update/\\\?token=$TOKEN&username=\$user&app=mikrotik&nas\
        ip=\$NAS&pd=\$prefixo\"\r\
        \n/tool fetch url=\"$LINKDOSGP/ws/radius/ipv6/update/\\\?token=$TOKEN&username=\$user&app=mikrotik&nasip=\$NAS&\
        pd=\$prefixo\" mode=http as-value output=user\r\
        \n}" [find .id!=999]
    /ppp profile set on-down=":local servernam\
        e \"<pppoe-\$user>\"\r\
        \n/ipv6 dhcp-server binding remove [find server=\$servername]\r\
        \n:local servername \"<pppoe-\$user>\"\r\
        \n/ipv6 dhcp-server remove [find numbers=\$user]\r\
        \n" [find .id!=999]
    } else={
    :log info "############\nSERVICO IPV6 DESATIVADO NO EQUIPAMENTO\n############"
    }
    }
}

#CONFIGURANDO BACKUP DE SECRETS:

ppp secret export verbose compact file="secretsBKP-SGP.txt"
:global wurl "ws/mikrotik/login/local"
/system script
add name=sgp_login_local owner=SGP policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source=":global filename \"sgp_login_local.txt\";\r\
    \n/file remove [/file find name=\$filename]\r\
    \n/tool fetch url=\"$LINKDOSGP/$wurl/\\?token=$TOKEN&app=mikrotik&nas=$NAS&disabled=1\" duration=30 dst-path=\$filename;\r\
    \n:delay 32s;\r\
    \n/import file-name=\$filename;"
/system scheduler
add disabled=no interval=6h name=sgp_login_local on-event=sgp_login_local policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=12:00:00
/tool netwatch
add comment="HABILITA SECRETES CASO O RADIUS-SGP $RADIUS PARE" disabled=yes \
    down-script="/ppp secret ; :foreach i in [ find comment~\"SGP:\
    \" ] do={ enable \$i }; /ppp active; :foreach p in [find \\ radius=no] do=\
    { remove \$p; :delay 1};" host=$RADIUS interval=3m timeout=10000ms \
    up-script="/ppp secret ; :foreach i in [ find comment~\"SGP:\" ] do={ disa\
    ble \$i }; /ppp active; :foreach p in [find \\ radius=no] do={ remove \$p;\
    \_:delay 1};"

:log print where message="SERVICO IPV6 HABILITADO NO EQUIPAMENTO" or message="SERVICO IPV6 DESATIVADO NO EQUIPAMENTO"

#Script Integração
#Systema de Gerenciamento de provedores - SGP

#CONFIGURANDO VARIAVEIS NO SGP:

from apps.admcore.models import Config

Config.objects.create(
    var='ATRASO_HTML',
    description='PAGINA DE ATRASO',
    value='<!DOCTYPE html> <html> <head> <title></title> <meta http-equiv="Content-Type" content="text/html; charset=utf-8"> <style type="text/css"> html { height: 100%; } body { font-family: Arial, sans-serif; font-size: 16px; height: 100%; margin: 0; background-repeat: no-repeat; background-attachment: fixed; overflow: hidden; background: -moz-linear-gradient(19% 75% 90deg, #fff, #ddd); background: -webkit-gradient(linear, 0% 0%, 0% 100%, from(#ddd), to(#fff)); background-repeat: repeat-x; } h1 { font-size: 7em; color: #bebebe; line-height: 16px; } h2 { font-size: 3em; letter-spacing: -0.05em; } .content { text-align: center; } a, a:visited { color: #43640a; } p { padding: 0 20%; } </style> </head> <body> <div class="content"> <h1>!</h1> <h2>Aviso</h2> <p>Não consta em nosso sistema o registro de pagamento das últimas faturas. Caso ainda haja alguma pendência, queira por gentileza regularizar o mais breve possível, após 15 dias de atraso o sistema bloqueará automaticamente o serviço. Caso já tenha regularizado e está mensagem continue aparecendo, Por favor!! entrar em contato com a $PROVEDOR. Favor entrar em contato nos telefones <strong>(xx) xxxxx-xxxx</strong> </p> </div> </body> </html>',
    active=True
).save()

Config.objects.create(
    var='BLOQUEIO_HTML',
    description='PAGINA DE BLOQUEIO',
    value='<!DOCTYPE html> <html> <head> <title></title> <meta http-equiv="Content-Type" content="text/html; charset=utf-8"> <style type="text/css"> html { height: 100%; } body { font-family: Arial, sans-serif; font-size: 16px; height: 100%; margin: 0; background-repeat: no-repeat; background-attachment: fixed; overflow: hidden; background: -moz-linear-gradient(19% 75% 90deg, #fff, #ddd); background: -webkit-gradient(linear, 0% 0%, 0% 100%, from(#ddd), to(#fff)); background-repeat: repeat-x; } h1 { font-size: 7em; color: #bebebe; line-height: 16px; } h2 { font-size: 3em; letter-spacing: -0.05em; } .content { text-align: center; } a, a:visited { color: #43640a; } p { padding: 0 20%; } </style> </head> <body> <p align="center"> <img width="350px" src="$LINKDOSGP/media/img/ASSINATURA.png"/></p> <div class="content"> <h1>!</h1> <h2>Acesso indisponível $PROVEDOR !!!</h2></h2><p>Favor entrar em contato nos telefones <strong>(xx) xxxxx-xxxx</strong> </p> </div> </body> </html>',
    active=True
).save()

Config.objects.create(
    var='BLOQUEIO_V6_PREFIX',
    description='Suspensão de clientes IPv6',
    value='bloqueiov6prefix',
    active=True
).save()

Config.objects.create(
    var='BLOQUEIO_V6_PD',
    description='Suspensão de clientes IPv6',
    value='bloqueiov6pd',
    active=True
).save()

from apps.netcore.utils.radius import manage
print("Executando Reload Radius")
manage.Manage().ResetRadius()
print("Reload Radius finalizado")

EOF

subl Mikrotik-$PROVEDOR.txt
}

Huawei () {
clear
echo "Script - Integrao Huawei-NE20/40/8000"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do Provedor:"
read PROVEDOR
echo "Secrets Radius: (Mnimo de 16 caracters)"
read SECRETS
echo "IP do Radius:"
read IP_RADIUS
echo "IP do NAS:"
read IP_NAS
echo "Porta do authentication:"
read AUTH_PORT
echo "Porta do accounting:"
read ACCT_PORT
echo "Interface IP NAS: (Ex: loopback0)"
read INTERFACE
echo "Nome do Pool IPv4:"
read POOLV4
echo "Nome do Pool IPv6-PD:"
read POOLPDV6
echo "Nome do Pool IPv6-Prefix:"
read POOLPREFIXOV6

cat <<EOF > Huawei-$PROVEDOR.txt

system-view

radius-server group sgp-$PROVEDOR
radius-server shared-key-cipher $SECRETS
radius-server authentication $IP_RADIUS source ip-address $IP_NAS $AUTH_PORT weight 0
radius-server accounting $IP_RADIUS source ip-address $IP_NAS $ACCT_PORT weight 0
commit
radius-server type standard
undo radius-server user-name domain-included
radius-server traffic-unit byte
commit
radius-server source interface $INTERFACE
radius-attribute case-sensitive qos-profile-name
radius-server format-attribute nas-port-id vendor redback-simple
commit
radius-server accounting-stop-packet send force
radius-server retransmit 5 timeout 10
radius-server accounting-start-packet resend 3
commi
radius-server accounting-stop-packet resend 3
radius-server accounting-interim-packet resend 5
radius-attribute assign hw-mng-ipv6 pppoe motm
commi
radius-attribute apply framed-ipv6-pool match pool-type
radius-attribute apply user-name match user-type ipoe
radius-attribute service-type value outbound user-type ipoe
commit
quit

radius local-ip all
commit
radius-server authorization $IP_RADIUS destination-port 3799 server-group sgp-$PROVEDOR shared-key $SECRETS
commit

ip pool bloqueados bas local
gateway 10.24.0.1 255.255.252.0
section 0 10.24.0.2 10.24.3.254
commit
quit
ipv6 prefix bloqueiov6prefix local
prefix 2001:DC8:100::/40
commit
quit
ipv6 prefix bloqueiov6pd delegation
prefix 2001:DB8:900::/40 delegating-prefix-length 56
commit
quit
ipv6 pool bloqueiov6prefix bas local 
dns-server 2001:4860:4860::8888
prefix bloqueiov6prefix
commit
quit
ipv6 pool bloqueiov6pd bas delegation 
dns-server 2001:4860:4860::8888
prefix bloqueiov6pd
commit
quit

aaa
authentication-scheme auth_$PROVEDOR
authentication-mode radius local
commit
quit
accounting-scheme acct_$PROVEDOR
accounting interim interval 5
accounting send-update
commit
quit

aaa
domain $PROVEDOR-sgp
authentication-scheme auth_$PROVEDOR
accounting-scheme acct_$PROVEDOR
commit
radius-server group sgp-$PROVEDOR
dns primary-ip 8.8.8.8
commit
dns second-ip 8.8.4.4
dns primary-ipv6 2001:4860:4860::8888
commit
dns second-ipv6 2001:4860:4860::8844
qos rate-limit-mode car inbound
commit
qos rate-limit-mode car outbound
ip-pool $POOLV4
commit
ipv6-pool $POOLPDV6
ipv6-pool $POOLPREFIXOV6
accounting-start-delay 10 online user-type ppp ipoe static
commit
quit

aaa
domain bloqueados
authentication-scheme auth_$PROVEDOR
accounting-scheme acct_$PROVEDOR
commit
radius-server group sgp-$PROVEDOR
commit
ip-pool bloqueados
commit  
ipv6-pool bloqueiov6prefix
commit
ipv6-pool bloqueiov6pd
commit  
dns primary-ip 8.8.8.8
dns second-ip 8.8.4.4
commit
dns primary-ipv6 2001:4860:4860::8888
commit
dns second-ipv6 2001:4860:4860::8844
commit
quit

snmp-agent community read cipher SGP_HUAWEI_GRAPHICs
snmp-agent sys-info version v2c
commit
quit

return
save
y

########################################################### CONFIGURACOES NO SGP #######################################################################

#Variaveis

from apps.admcore.models import Config

Config.objects.create(
    var='BLOQUEIO_V6_PREFIX',
    description='Suspensão de clientes IPv6',
    value='bloqueiov6prefix',
    active=True
).save()

Config.objects.create(
    var='BLOQUEIO_V6_PD',
    description='Suspensão de clientes IPv6',
    value='bloqueiov6pd',
    active=True
).save()

Config.objects.create(
    var='HUAWEI_RATE',
    description='Controle de banda via radius - Dinâmico',
    value='1',
    active=True
).save()

Config.objects.create(
    var='BLOQUEIO_HUAWEI_DOMAIN',
    description='Variável que redireciona o cliente para o domain bloqueados',
    value='bloqueados',
    active=True
).save()

Config.objects.create(
    var='HUAWEI_POOL_ENABLE',
    description='Habilita o envio do pool name',
    value='1',
    active=True
).save()

from apps.netcore import models
models.IPPool.objects \
    .create(name="bloqueados",
            iprange="10.24.0.0/22")

from apps.cauth.models import Token, Application

from apps.netcore.utils.radius import manage
print("Executando Reload Radius")
manage.Manage().ResetRadius()
print("Reload Radius finalizado")

EOF

subl Huawei-$PROVEDOR.txt
}

Cisco () {
clear
echo "Script - Integrao Cisco"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do Provedor:"
read PROVEDOR
echo "Secrets Radius: (Mnimo de 16 caracters)"
read SECRETS
echo "IP do Radius:"
read IP_RADIUS
echo "Porta do authentication:"
read AUTH_PORT
echo "Porta do accounting:"
read ACCT_PORT
echo "Interface IP NAS: (Ex: $INTERFACE)"
read INTERFACE
echo "Nome do Pool IPv4:"
read POOLV4
echo "Nome do Pool IPv6-PD:"
read POOLPDV6
echo "Nome do Pool IPv6-Prefix:"
read POOLPREFIXOV6

cat <<EOF > cisco-$NOME_PROV.txt

conf t

aaa group server radius SGP-$PROVEDOR
server-private $IP_RADIUS auth-port $AUTH_PORT acct-port $ACCT_PORT key $SECRETS
ip radius source-interface $INTERFACE
!
aaa authentication login default local
aaa authentication login SGP-$PROVEDOR group SGP-$PROVEDOR
aaa authentication enable default enable
aaa authentication ppp default group radius local
aaa authentication ppp SGP-$PROVEDOR group SGP-$PROVEDOR
aaa authorization console
aaa authorization config-commands
aaa authorization exec default local 
aaa authorization exec SGP-$PROVEDOR group SGP-$PROVEDOR 
aaa authorization network default group radius 
aaa authorization network SGP-$PROVEDOR group SGP-$PROVEDOR 
aaa authorization configuration default group management 
aaa authorization configuration SGP-$PROVEDOR group SGP-$PROVEDOR 
aaa authorization subscriber-service default local group radius 
aaa authorization subscriber-service SGP-$PROVEDOR local group SGP-$PROVEDOR 
aaa accounting delay-start all
aaa accounting session-duration ntp-adjusted
aaa accounting update periodic 20
aaa accounting include auth-profile framed-ip-address
aaa accounting include auth-profile framed-ipv6-prefix
aaa accounting include auth-profile delegated-ipv6-prefix
aaa accounting exec default start-stop group radius
aaa accounting exec SGP-$PROVEDOR start-stop group SGP-$PROVEDOR
aaa accounting network default start-stop group radius
aaa accounting network pppoe start-stop group management
aaa accounting network SGP-$PROVEDOR start-stop group SGP-$PROVEDOR
aaa accounting system default start-stop group radius
!
!
aaa server radius dynamic-author
client $IP_RADIUS server-key $SECRETS
server-key $SECRETS
port 3799
auth-type any
ignore session-key
!
!
policy-map SGP-DOWNLOAD
class class-default
police cir 1000000
exceed-action drop 
!
policy-map SGP-UPLOAD
class class-default
police cir 1024000
exceed-action drop 
!
interface Virtual-Template10
 mtu 1492
 ip unnumbered $INTERFACE
 no ip redirects
 no ip unreachables
 no ip proxy-arp
 ip nat inside
 ip tcp adjust-mss 1452
 no logging event link-status
 peer ip address forced
 peer default ip address pool $POOLV4
 peer default ipv6 pool $POOLPREFIXOV6
 ipv6 unnumbered $INTERFACE
 ipv6 mtu 1492
 ipv6 nd ns-interval 1000
 ipv6 nd prefix default no-advertise
 ipv6 nd managed-config-flag
 ipv6 nd other-config-flag
 ipv6 nd router-preference High
 no ipv6 nd ra suppress
 ipv6 nd ra lifetime 21600
 ipv6 nd ra interval 4 3
 ipv6 dhcp server $POOLPDV6 allow-hint
 no snmp trap link-status
 keepalive 60 2
 ppp max-bad-auth 8
 ppp mtu adaptive
 ppp disconnect-cause keepalive lost-carrier
 ppp authentication pap chap ms-chap ms-chap-v2 SGP-$PROVEDOR
 ppp authorization SGP-$PROVEDOR
 ppp accounting SGP-$PROVEDOR
 ppp ipcp dns 8.8.8.8 1.1.1.1
 ppp ipcp ignore-map
 ppp ipcp address required
 ppp ipcp address unique
 ppp link reorders
 ppp timeout authentication 100
 service-policy input SGP-UPLOAD
 service-policy output SGP-DOWNLOAD
 ip virtual-reassembly
!
bba-group pppoe SGP-$PROVEDOR
virtual-template 10
vendor-tag circuit-id service
vendor-tag remote-id service
sessions per-mac limit 1
sessions per-vlan limit 16000
pado delay 0
!
radius server SGP-$PROVEDOR
address ipv4 $IP_RADIUS auth-port $AUTH_PORT acct-port $ACCT_PORT
key $SECRETS
!
ip local pool bloqueados 10.24.0.1 10.24.3.254
!
ipv6 local pool bloqueiov6pd 2001:DB1:100::/43 56
ipv6 local pool bloqueiov6prefix 2001:DB8:200::/48 64
!
ipv6 dhcp pool bloqueiov6pd
prefix-delegation pool bloqueiov6pd lifetime 1800 600
dns-server 2001:4860:4860::8888
dns-server 2001:4860:4860::8844
!
snmp-server community SGP-GRAPHICs RO
snmp-server host $IP_RADIUS version 2c SGP-GRAPHICs
!

########################################################### CONFIGURACOES NO SGP #######################################################################

from apps.admcore.models import Config

Config.objects.create(
    var='BLOQUEIO_V6_PREFIX',
    description='Suspensão de clientes IPv6',
    value='bloqueiov6prefix',
    active=True
).save()

Config.objects.create(
    var='BLOQUEIO_V6_PD',
    description='Suspensão de clientes IPv6',
    value='bloqueiov6pd',
    active=True
).save()

Config.objects.create(
    var='CISCO_DYNAMIC_POLICY',
    description='Controle de Banda via Radius',
    value='1',
    active=True
).save()

from apps.netcore import models
models.IPPool.objects \
    .create(name="bloqueados",
            iprange="10.24.0.0/22")

from apps.admcore import models
from apps.netcore.utils.radius import manage
m = manage.Manage()
models.PlanoInternet.objects.all().update(policy_out='SGP-DOWNLOAD')
models.PlanoInternet.objects.all().update(policy_in='SGP-UPLOAD')
for p in models.PlanoInternet.objects.all():
    m.delRadiusPlano(p)
    m.addRadiusPlano(p)
    print(p)

from apps.netcore.utils.radius import manage
print("Executando Reload Radius")
manage.Manage().ResetRadius()
print("Reload Radius finalizado")


########################################################### CONFIGURACOES INTERFACE #######################################################################

conf t

interface x/x/x
description PPPoE
pppoe enable group SGP-$PROVEDOR

EOF

subl cisco-$NOME_PROV.txt
}

Accel () {
clear
echo "Script - Integrao Accel-PPP"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do NAS:"
read NAS_NAME
echo "IP do NAS:"
read IP_NAS
echo "IP do Radius:"
read IP_RADIUS
echo "Secrets do Radius:"
read SECRETS
echo "Porta do authentication:"
read AUT_PORT
echo "Porta do accounting:"
read ACC_PORT
echo "Gateway Accel-PPP:"
read GW_IP_ADD

cat <<EOF > Accel-PPP-$NAS_NAME.txt

[radius]
dictionary=/usr/local/share/accel-ppp/radius/dictionary  
nas-identifier=$NAS_NAME
nas-ip-address=$IP_NAS
gw-ip-address=$GW_IP_ADD
server=$IP_RADIUS,$SECRETS,auth-port=$AUT_PORT,acct-port=$ACC_PORT,req-limit=50,fail-timeout=0,max-fail=10,weight=1
dae-server=$IP_NAS:3799,$SECRETS
acct-interim-interval=300
acct-timeout=0
max-try=30
acct-delay-time=0
interim-verbose=1
verbose=1
timeout=30
acct-on=0


#SHAPER ACCEL

[shaper]
vendor=Accel
attr=Filter-Id
ifb=ifb0
up-limiter=htb
down-limiter=tbf

#SHAPER MIKROTIK

[shaper]
vendor=Mikrotik
attr=Mikrotik-Rate-Limit
ifb=ifb0
up-limiter=htb
down-limiter=tbf
leaf-qdisc=fq_codel limit 512 flows 1024 quantum 1492 target 8ms interval 4ms noecn
verbose=1

outro exemplo:

[shaper]
verbose=1
vendor=Mikrotik
attr=Mikrotik-Rate-Limit
down-burst-factor=0.1
up-burst-factor=1.0
ifb=ifb0
up-limiter=police
down-limiter=tbf
rate-multiplier=1.088

#BLOQUEIO IPv6

[ipv6-pool]
attr-prefix=Delegated-IPv6-Prefix-Pool
attr-address=Framed-IPv6-Pool
fc00:158c:6c0::/42,64,name=bloqueiov6prefix
delegate=fc00:158c:700::/42,56,name=bloqueiov6pd

OBS:. Pools com o parmetro name devem ficar acima dos demais.

EOF

subl Accel-PPP-$NAS_NAME.txt
}

Juniper () {
clear
echo "Script - Integrao Juniper"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do Provedor:"
read NOME_PROV
echo "IP do Radius:"
read IP_RADIUS
echo "Secrets do Radius:"
read SECRETS
echo "IP do NAS:"
read IP_NAS
echo "Porta do authentication:"
read AUT_PORT
echo "Porta do accounting:"
read ACC_PORT

cat <<EOF > Juniper-$NOME_PROV.txt

conf 

set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables up-rate default-value 32k
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables up-rate mandatory
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables down-rate default-value 32k
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables down-rate mandatory
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables burst-up default-value 2m
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables burst-down default-value 2m
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables filter-up uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables filter-down uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables shaper-up uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 variables shaper-down uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 interfaces "\$junos-interface-ifd-name" unit "\$junos-interface-unit" family inet filter input "\$filter-up"
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 interfaces "\$junos-interface-ifd-name" unit "\$junos-interface-unit" family inet filter output "\$filter-down"
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall family inet filter "\$filter-up" interface-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall family inet filter "\$filter-up" term accept then policer "\$shaper-up"
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall family inet filter "\$filter-up" term accept then service-filter-hit
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall family inet filter "\$filter-up" term accept then accept
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall family inet filter "\$filter-down" interface-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall family inet filter "\$filter-down" term accept then policer "\$shaper-down"
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall family inet filter "\$filter-down" term accept then service-filter-hit
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall family inet filter "\$filter-down" term accept then accept
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-up" filter-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-up" logical-interface-policer
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-up" if-exceeding bandwidth-limit "\$up-rate"
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-up" if-exceeding burst-size-limit "\$burst-up"
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-up" then discard
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-down" filter-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-down" logical-interface-policer
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-down" if-exceeding bandwidth-limit "\$down-rate"
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-down" if-exceeding burst-size-limit "\$burst-down"
set dynamic-profiles SGP-$NOME_PROV-Limit-V4 firewall policer "\$shaper-down" then discard

set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables up-rate default-value 32k
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables up-rate mandatory
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables down-rate default-value 32k
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables down-rate mandatory
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables burst-up default-value 2m
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables burst-down default-value 2m
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables filter-up-v6 uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables filter-down-v6 uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables shaper-up-v6 uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables shaper-down-v6 uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 interfaces "\$junos-interface-ifd-name" unit "\$junos-interface-unit" family inet6 filter input "\$filter-up-v6"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 interfaces "\$junos-interface-ifd-name" unit "\$junos-interface-unit" family inet6 filter output "\$filter-down-v6"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-up-v6" interface-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-up-v6" term accept then policer "\$shaper-up-v6"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-up-v6" term accept then service-filter-hit
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-up-v6" term accept then accept
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-down-v6" interface-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-down-v6" term accept then policer "\$shaper-down-v6"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-down-v6" term accept then service-filter-hit
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-down-v6" term accept then accept
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" filter-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" logical-interface-policer
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" if-exceeding bandwidth-limit "\$up-rate"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" if-exceeding burst-size-limit "\$burst-up"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" then discard
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" filter-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" logical-interface-policer
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" if-exceeding bandwidth-limit "\$down-rate"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" if-exceeding burst-size-limit "\$burst-down"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" then discard

set access radius-server $IP_RADIUS port $AUT_PORT
set access radius-server $IP_RADIUS accounting-port $ACC_PORT
set access radius-server $IP_RADIUS secret $SECRETS
set access radius-server $IP_RADIUS timeout 40
set access radius-server $IP_RADIUS retry 3
set access radius-server $IP_RADIUS accounting-timeout 20
set access radius-server $IP_RADIUS accounting-retry 6
set access radius-server $IP_RADIUS source-address $IP_NAS
set access radius-disconnect-port 3799
set access radius-disconnect $IP_RADIUS secret $SECRETS

set access profile SGP-$NOME_PROV accounting-order radius
set access profile SGP-$NOME_PROV authentication-order radius
set access profile SGP-$NOME_PROV domain-name-server-inet 8.8.8.8
set access profile SGP-$NOME_PROV domain-name-server-inet 8.8.4.4
set access profile SGP-$NOME_PROV domain-name-server-inet6 2001:4860:4860::8888
set access profile SGP-$NOME_PROV domain-name-server-inet6 2001:4860:4860::8844
set access profile SGP-$NOME_PROV radius authentication-server $IP_RADIUS
set access profile SGP-$NOME_PROV radius accounting-server $IP_RADIUS
set access profile SGP-$NOME_PROV radius options nas-identifier 4
set access profile SGP-$NOME_PROV radius options nas-port-id-delimiter "%"
set access profile SGP-$NOME_PROV radius options nas-port-id-format nas-identifier
set access profile SGP-$NOME_PROV radius options nas-port-id-format interface-description
set access profile SGP-$NOME_PROV radius options nas-port-type ethernet ethernet
set access profile SGP-$NOME_PROV radius options calling-station-id-delimiter :
set access profile SGP-$NOME_PROV radius options calling-station-id-format mac-address
set access profile SGP-$NOME_PROV radius options accounting-session-id-format decimal
set access profile SGP-$NOME_PROV radius options client-authentication-algorithm direct
set access profile SGP-$NOME_PROV radius options client-accounting-algorithm direct
set access profile SGP-$NOME_PROV radius options service-activation dynamic-profile required-at-login
set access profile SGP-$NOME_PROV accounting order radius
set access profile SGP-$NOME_PROV accounting coa-immediate-update
set access profile SGP-$NOME_PROV accounting update-interval 10
set access profile SGP-$NOME_PROV accounting statistics volume-time
set access domain map default access-profile SGP-$NOME_PROV

set access address-assignment pool bloqueiov6prefix family inet6 prefix 2001:D08:100::/40
set access address-assignment pool bloqueiov6prefix family inet6 range ipv6-pppoe prefix-length 64
set access address-assignment pool bloqueiov6pd family inet6 prefix 2001:DB8:900::/40
set access address-assignment pool bloqueiov6pd family inet6 range prefixn-range prefix-length 64

commit

########################################################### CONFIGURACOES NO SGP #######################################################################

#Setar profile nos planos do SGP em Lote:

Menu: TSMX/WebShell Script

radius={
  "reply": [
    {
      "attribute": "ERX-Service-Activate:1",
      "value": "\"SGP-$NOME_PROV-Limit-V4({upload}M,{download}M)\"",
      "op": "+="
    },
    {
      "attribute": "ERX-Service-Activate:2",
      "value": "\"SGP-$NOME_PROV-Limit-V6({upload}M,{download}M)\"",
      "op": "+="
    }
  ]
}
from apps.admcore import models
from apps.netcore.utils.radius import manage
print(models.PlanoInternet.objects.all().update(radius_json=radius))
m = manage.Manage()
for i in models.PlanoInternet.objects.all():
    m.delRadiusPlano(i)
    m.addRadiusPlano(i)

#Variaveis

Nome : BLOQUEIO_V6_PREFIX
Descrição: Suspensão de clientes IPv6
Valor : bloqueiov6prefix

Nome : BLOQUEIO_V6_PD
Descrição: Suspensão de clientes IPv6
Valor : bloqueiov6pd

Nome : ERX_POOL_ENABLE
Descrição: ERX_POOL_ENABLE
Valor : 1

#RebuildRadius

from apps.netcore.utils.radius import manage
print("recriar radius Iniciando")
manage.Manage().ResetRadius()
print("Finalizado")

#Troubleshooting

ping $IP_RADIUS source $IP_NAS

test aaa ppp username teste-sgp password 1234567890 profile SGP-$NOME_PROV

show configuration | display set

EOF

subl Juniper-$NOME_PROV.txt
}

Voltar() {
    clear
        Menu
}

Sair() {
    clear
    exit
}
clear
Menu
