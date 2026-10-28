# Histórico de versões

## 1.4.0 — em validação (não publicada)

- **Resumo com semáforo** no topo do relatório: [OK], [ATENÇÃO], [FALHA], [INFO] ou [NÃO TESTADO] para link, endereço IPv4, gateway, DNS, internet (informada pelo Windows), estabilidade, 802.1X e switch, com o motivo de cada item.
- **Estado da autenticação 802.1X** da porta, lido do serviço de autenticação com fio do Windows (`netsh lan`).
- **Teste de estabilidade (60 s)**: um ping por segundo com origem na Ethernet, perda, latência, jitter, maior sequência sem resposta e erros/descartes do adaptador ocorridos durante o teste.
- **Levantamento de pontos**: campo de etiqueta do ponto, botão "Registrar ponto" (linha com link, velocidade, IP, gateway, MAC do gateway, DHCP, 802.1X, switch, porta, VLAN, IP e MAC do switch e resultados) e "Exportar levantamento" em CSV (separador ponto e vírgula, abre no Excel). Fica em memória até exportar.
- O equipamento identificado por LLDP/CDP passa a aparecer no relatório e no levantamento.
- Proteção contra misturar pontos: quando o link muda, ou ao registrar um ponto, os resultados anteriores saem do resumo.

## 1.3.0 — em validação (não publicada)

- **Wi-Fi** (botão próprio, seção separada da Ethernet): interface sem fio, SSID, access point conectado (BSSID) com prefixo OUI, canal, faixa, sinal e lista de access points próximos. Usa `netsh wlan`; não exige administrador. No Windows 11 pode exigir os serviços de localização ligados.
- **Switch (LLDP/CDP)**, experimental: captura de cerca de 65 s com o `pktmon` do Windows, restrita à Ethernet quando o componente é identificado, e decodificação de nome do switch, porta, descrição, VLAN nativa, VLAN de voz (LLDP-MED/CDP), IP de gerência, plataforma e anúncio de PoE. **Exige PowerShell como administrador**, pede confirmação e cria dois arquivos temporários na pasta TEMP, apagados ao final. Depende de o switch enviar os anúncios.
- Correção: mensagens dos eventos do driver mostravam apenas o nome do adaptador (driver Intel); agora mostram o texto do evento.
- Correção: espaço vazio abaixo dos botões.

## 1.2.0 — em validação (não publicada)

- Nova distribuição em script único `DiagnosticoRJ45.ps1` (Windows PowerShell 5.1), para computadores em que a política de reputação de executáveis do Defender bloqueia EXE sem histórico. Não compila código, não grava arquivos e não pede elevação. O EXE 1.1.0 continua no repositório.
- Seleção automática da Ethernet com link ativo, sem preferência fixa por modelo; adaptadores USB e docks Ethernet são aceitos pelo tipo de mídia 802.3. Wi-Fi, VPN e adaptadores virtuais continuam excluídos.
- Histórico de eventos do driver no log Sistema (últimos 7 dias), útil para quedas e retornos de link.
- Teste ativo de DNS em cada servidor da Ethernet, executado somente quando a rota até o servidor é a Ethernet selecionada.
- Teste ativo IPv6 (gateway de enlace local com escopo fixado na interface, ou destino global com origem explícita).
- MAC do gateway com prefixo OUI e identificação de MAC virtual HSRP/VRRP/GLBP; contagem de vizinhos IPv4.
- IPv4 duplicado conforme detecção do Windows.
- Teste de MTU do caminho com pacotes sem fragmentação.
- Rastreamento de rota IPv4 com origem na Ethernet.
- Comparação das rotas padrão ativas (Ethernet × Wi-Fi) e aviso quando o tráfego comum sai por outra interface.
- Duplex informado pelo driver, velocidade/duplex configurado no driver, perfil de rede e conectividade informada pelo Windows.
- Resultados de testes acumulados em memória por adaptador durante a sessão; botão para copiar o relatório.

## 1.1.0 — 2026-10-20

- Consulta direta por .NET/WMI e APIs IP Helper, sem iniciar PowerShell ou ping.
- MAC local, máscara, IPv6, DHCP, servidor DHCP e datas de concessão no relatório.
- Teste ICMP com origem explícita, rota restrita ao adaptador e resumo de latência.
- Link de 100 Mb/s apresentado como característica observada, sem presumir defeito.
- Manifesto `asInvoker`: sem solicitação automática de administrador.
- Tratamento de erro na exportação e teste nativo de rota/ICMP em loopback.
- Nenhuma alteração automática de políticas de segurança pelo aplicativo. A regra de reputação do Defender pode continuar bloqueando o EXE sem assinatura.

## Documentação — 2026-10-20

- Código original e executáveis disponibilizados sob a Unlicense, incluindo as versões 1.0.0 e 1.0.1.
- Repositório preparado para acesso público, com relatórios locais fora do histórico Git.

## 1.0.1 — 2026-10-20

- Distribuição portátil com um único executável, sem configuração externa ou gravação automática de logs.
- Removida geração de arquivos dos modos de verificação e removido o modo de captura de imagem.
- Relatórios permanecem em memória; exportação apenas por escolha explícita do usuário.
- CI verifica os modos de diagnóstico em uma pasta com somente o executável e detecta arquivos auxiliares criados nessa pasta.
- Adaptadores sem interface IP disponível continuam visíveis, com indicação dessa condição, sem impedir a consulta dos demais.


## 1.0.0 — 2026-10-20

- Versão inicial do aplicativo Windows para diagnóstico RJ45.
- Seleção automática da Intel I219-LM e seleção manual de outras interfaces Ethernet físicas.
- Consulta de link, velocidade negociada, configuração IPv4 e contadores do adaptador.
- Teste ICMP com origem e rota validadas pela interface selecionada.
- Acompanhamento de link e exportação de relatório.
- Compilação reproduzível, testes de interpretação e publicação pelo GitHub Actions.

Pendências: testes físicos com cabo conectado, homologação em outros computadores e liberação corporativa do executável. Sem certificação de cabeamento ou integração TDR validada.
