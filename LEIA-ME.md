# Diagnóstico RJ45 — versão portátil 1.1.0

## Versão 1.3.0 em PowerShell (em validação)

Copie somente `DiagnosticoRJ45.ps1`. Clique com o botão direito e escolha **Executar com o PowerShell**. A janela preta do PowerShell precisa ficar aberta enquanto o aplicativo é usado. Se o Windows informar que o script não está assinado porque veio da internet, abra as Propriedades do arquivo e marque **Desbloquear**, desde que isso seja permitido pela política da empresa.

Botões: **Atualizar**, **Teste completo**, **IPv4 (10 pacotes)**, **DNS**, **IPv6**, **MTU**, **Rastrear rota**, **Copiar relatório** e **Salvar relatório**. Campo Destino em branco usa o gateway da Ethernet. Todos os testes usam a Ethernet selecionada; o que sairia pelo Wi-Fi é recusado com explicação. O relatório inclui eventos do driver, rotas padrão (Ethernet × Wi-Fi), MAC do gateway, duplex e configuração de velocidade do driver.

**Wi-Fi** mostra o access point conectado (BSSID), canal, sinal e redes próximas, em seção separada. **Switch (LLDP/CDP)** é experimental: exige o PowerShell aberto como administrador, captura por cerca de 65 segundos e mostra nome do switch, porta e VLAN quando o switch envia esses anúncios. Essa função cria dois arquivos temporários na pasta TEMP e os apaga ao final.

O PowerShell do Windows pode manter seus próprios caches de sistema; fora a função Switch, o script não cria arquivos.

Código aberto e uso livre sob a Unlicense, sem cobrança, ativação ou chave de licença. A declaração está no arquivo LICENSE do repositório; ele não precisa acompanhar o EXE para executar a ferramenta. O aplicativo continua sujeito às políticas de segurança do Windows.

É necessário somente o `DiagnosticoRJ45.exe`. Pode ser movido para outra pasta ou pendrive, sem instalação. Não cria configuração, logs, banco de dados ou arquivos temporários próprios. Resultados ficam na memória; use **Salvar relatório** apenas se quiser exportá-los para um local escolhido. Utiliza componentes do Windows descritos abaixo e continua sujeito às políticas corporativas.

Abra `DiagnosticoRJ45.exe`, conecte o cabo a um switch ou roteador ligado e clique em **Atualizar**. A Intel I219-LM é selecionada por padrão neste HP EliteBook 640 G11. Em outros computadores, o aplicativo enumera placas Ethernet físicas e permite selecionar a desejada.

O aplicativo mostra link, velocidade negociada, IPv4, gateway, DNS configurado e contadores acumulados de tráfego, erros e descartes. **Acompanhar link** consulta a cada oito segundos; eventos mais curtos podem passar despercebidos. A tela registra mudanças entre estados observados. A atualização substitui o relatório da tela; salve resultados antes de voltar a acompanhar.

**Testar IPv4** envia dez pings para o gateway ou o IPv4 informado. A origem é o IPv4 da Ethernet selecionada. Antes de cada pacote, a rota deve corresponder à mesma interface; se não corresponder, o teste para, evitando um resultado pela conexão Wi-Fi. Resposta bloqueada por firewall não prova defeito no cabo. O teste pode levar cerca de um minuto, dependendo das consultas do Windows. Esta versão requer IPv4 e não executa teste de DNS, internet ou transferência de arquivos.

Os testes não alteram IP, drivers, configuração do adaptador nem firewall. Não requer instalação ou permissão de administrador para as consultas usuais. Políticas corporativas podem impedir consultas ou execução. O executável não tem assinatura digital.

Não mede pares, comprimento, distância até rompimentos, PoE, interferência ou certificação de categoria. Nenhuma interface TDR compatível foi validada com o driver 20.0.3.21 instalado. Uma conexão a 100 Mb/s pode ser limite do equipamento remoto ou configuração e não confirma falha do cabo. Os contadores são do adaptador, podem incluir tráfego anterior e não indicam a causa dos erros.

Requisitos: Windows 10/11 e .NET Framework 4.8. A versão 1.1.0 consulta diretamente .NET, WMI e IP Helper, sem executar PowerShell ou ping. Novas placas usam os dados padrão do Windows; recursos proprietários precisam de integração e validação específicas. O manifesto não exige elevação administrativa.

`compilar.ps1` recompila o código-fonte com o compilador .NET do Windows. `DiagnosticoRJ45.exe --self-test` verifica a interpretação de estados e consulta o hardware real sem gravar arquivos. `--unit-test` executa apenas verificações sem hardware. Ambos usam o código de saída para sinalizar falhas. Revise relatórios exportados manualmente antes de compartilhá-los, pois contêm configuração local da rede.

## Validação em 20/10/2026

A compilação foi concluída. A execução inicial passou nas verificações de estados e identificou a Intel I219-LM, driver 20.0.3.21, sem link. Depois de um ajuste de captura da prévia da interface, a versão recompilada foi impedida de executar pela política corporativa do Microsoft Defender Exploit Guard, evento 1121, regra 01443614-CD74-433A-B99E-2ECDC07BFC25. A versão final não teve execução validada. É necessária liberação formal da TI para prosseguir; nenhuma política de segurança foi alterada. Não foi realizado teste ativo com cabo conectado.
