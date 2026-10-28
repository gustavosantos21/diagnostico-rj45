# Validação

Estado separado por tipo de evidência. Atualizado em 28/10/2026.

## 1.1.0 (EXE)

- **Testado automaticamente:** compilação e modos `--unit-test` / `--self-test` no GitHub Actions (windows-latest).
- **Validado no equipamento:** apenas a consulta inicial da versão 1.0 (Intel I219-LM, driver 20.0.3.21, sem cabo).
- **Bloqueado:** a execução no notebook corporativo foi impedida pelo Microsoft Defender (evento 1121, regra ASR 01443614-CD74-433A-B99E-2ECDC07BFC25, reputação de executáveis). Nenhuma política foi alterada.

## 1.2.0 (script PowerShell)

- **Implementado:** `DiagnosticoRJ45.ps1`, com as funções descritas no CHANGELOG.
- **Testado automaticamente (fora do Windows):** análise de sintaxe e `-UnitTest` (interpretação de saídas do ping em português e inglês, IPv4/IPv6, máscaras, avaliação do link, MAC virtual) em PowerShell 7 no Linux. A interface gráfica e os comandos de rede do Windows não puderam ser executados nesse ambiente.
- **Testado automaticamente (Windows):** aprovado no GitHub Actions em 28/10/2026 (execução 40750566895, versão 1.4.0, windows-latest, Windows PowerShell 5.1): análise de sintaxe, `-UnitTest`, `-SelfTest` (rota e ICMP de loopback e inventário em texto) e ausência de arquivos auxiliares na pasta do script. A interface gráfica não é exercitada no CI.
- **Validado no equipamento:** pendente.

### Primeira execução real (28/10/2026, outro computador com PowerShell liberado)

- **Validado:** a interface abriu; a Intel I219-LM foi listada e selecionada com link ativo; o histórico de eventos do driver foi lido (21 eventos em 7 dias, IDs 27 e 33).
- **Problema encontrado e corrigido na 1.3.0:** o texto dos eventos mostrava só o nome do adaptador; havia espaço vazio abaixo dos botões.
- **Não validado ainda:** os demais campos do relatório e os testes ativos.
- No notebook corporativo, o PowerShell também está bloqueado por política ("Restrictions"); não foi possível executar lá.

## 1.3.0 — implementada, não validada no equipamento

- **Testado automaticamente (fora do Windows):** sintaxe e 44 verificações, incluindo saídas do `netsh` em inglês e português, quadros LLDP e CDP sintéticos e leitura de arquivo pcapng.
- **Pendente no equipamento:** botão Wi-Fi (sem administrador) e botão Switch (como administrador, numa porta de switch que envie LLDP ou CDP).

## 1.4.0 — implementada, não validada no equipamento

- **Testado automaticamente (fora do Windows):** sintaxe e 58 verificações, incluindo estatística de estabilidade, estados 802.1X em inglês e português, regras do semáforo e geração do CSV do levantamento.
- **Pendente no equipamento:** todos os recursos novos.

## Roteiro de validação no equipamento

1. Abrir o script com o PowerShell padrão, sem administrador; confirmar que a janela abre e a Ethernet é selecionada.
2. Sem cabo: estado SEM LINK. Com cabo: velocidade, IPv4, gateway, DNS e DHCP coerentes com `ipconfig /all`.
3. IPv4 (10 pacotes), DNS, IPv6, MTU e Rastrear rota, com Wi-Fi desligado.
4. Repetir com Wi-Fi conectado: os resultados devem continuar sendo da Ethernet, e a seção de rotas deve indicar qual interface é a preferida.
5. Desconectar e reconectar o cabo com "Acompanhar link" ligado; conferir contagem de mudanças e eventos do driver.
6. Salvar e copiar relatório; confirmar que nenhum outro arquivo foi criado na pasta do script.
7. Wi-Fi: conferir SSID, BSSID, canal e sinal com `netsh wlan show interfaces`.
8. Switch: abrir o PowerShell como administrador, rodar o botão e conferir com a TI o nome do switch, porta e VLAN; confirmar que os arquivos temporários foram apagados.
9. Estabilidade (60 s) com o cabo firme e, num segundo teste, desconectando por alguns segundos: conferir perda e sequência sem resposta.
10. Registrar dois pontos diferentes e exportar o levantamento; abrir o CSV no Excel e conferir que os resultados de um ponto não aparecem no outro.
11. 802.1X: conferir o estado com a TI numa porta com e sem autenticação.
12. Repetir em outro computador e em adaptador USB Ethernet.

Nenhum desses testes certifica cabeamento.
