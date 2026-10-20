# Diagnóstico RJ45 — primeira versão

Abra `DiagnosticoRJ45.exe`, conecte o cabo a um switch ou roteador ligado e clique em **Atualizar**. A Intel I219-LM é selecionada por padrão neste HP EliteBook 640 G11. Em outros computadores, o aplicativo enumera placas Ethernet físicas e permite selecionar a desejada.

O aplicativo mostra link, velocidade negociada, IPv4, gateway, DNS configurado e contadores acumulados de tráfego, erros e descartes. **Acompanhar link** consulta a cada oito segundos; eventos mais curtos podem passar despercebidos. A tela registra mudanças entre estados observados. A atualização substitui o relatório da tela; salve resultados antes de voltar a acompanhar.

**Testar IPv4** envia dez pings para o gateway ou o IPv4 informado. A origem é o IPv4 da Ethernet selecionada. Antes de cada pacote, a rota deve corresponder à mesma interface; se não corresponder, o teste para, evitando um resultado pela conexão Wi-Fi. Resposta bloqueada por firewall não prova defeito no cabo. O teste pode levar cerca de um minuto, dependendo das consultas do Windows. Esta versão requer IPv4 e não executa teste de DNS, internet ou transferência de arquivos.

Os testes não alteram IP, drivers, configuração do adaptador nem firewall. Não requer instalação ou permissão de administrador para as consultas usuais. Políticas corporativas podem impedir consultas ou execução. O executável não tem assinatura digital.

Não mede pares, comprimento, distância até rompimentos, PoE, interferência ou certificação de categoria. Nenhuma interface TDR compatível foi validada com o driver 20.0.3.21 instalado. Uma conexão a 100 Mb/s pode ser limite do equipamento remoto ou configuração e não confirma falha do cabo. Os contadores são do adaptador, podem incluir tráfego anterior e não indicam a causa dos erros.

Requisitos: Windows 10/11 com Windows PowerShell 5.1, módulos NetAdapter/NetTCPIP e .NET Framework 4.8. Novas placas usam os dados padrão do Windows; recursos proprietários precisam de integração e validação específicas.

`compilar.ps1` recompila o código-fonte com o compilador .NET do Windows. `DiagnosticoRJ45.exe --self-test` verifica a interpretação de estados e consulta o hardware real, gravando `verificacao-local.txt`. Este relatório contém configuração local da rede: revise antes de compartilhar. A validação inicial foi feita sem cabo conectado; o teste ativo precisa ser confirmado com cabo e switch disponíveis.

## Validação em 20/10/2026

A compilação foi concluída. A execução inicial passou nas verificações de estados e identificou a Intel I219-LM, driver 20.0.3.21, sem link. Depois de um ajuste de captura da prévia da interface, a versão recompilada foi impedida de executar pela política corporativa do Microsoft Defender Exploit Guard, evento 1121, regra 01443614-CD74-433A-B99E-2ECDC07BFC25. A versão final não teve execução validada. É necessária liberação formal da TI para prosseguir; nenhuma política de segurança foi alterada. Não foi realizado teste ativo com cabo conectado.
