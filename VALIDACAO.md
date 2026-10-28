# Validação

Estado separado por tipo de evidência. Atualizado em 28/10/2026.

## 1.1.0 (EXE)

- **Testado automaticamente:** compilação e modos `--unit-test` / `--self-test` no GitHub Actions (windows-latest).
- **Validado no equipamento:** apenas a consulta inicial da versão 1.0 (Intel I219-LM, driver 20.0.3.21, sem cabo).
- **Bloqueado:** a execução no notebook corporativo foi impedida pelo Microsoft Defender (evento 1121, regra ASR 01443614-CD74-433A-B99E-2ECDC07BFC25, reputação de executáveis). Nenhuma política foi alterada.

## 1.2.0 (script PowerShell) — implementada, não validada no equipamento

- **Implementado:** `DiagnosticoRJ45.ps1`, com as funções descritas no CHANGELOG.
- **Testado automaticamente (fora do Windows):** análise de sintaxe e `-UnitTest` (interpretação de saídas do ping em português e inglês, IPv4/IPv6, máscaras, avaliação do link, MAC virtual) em PowerShell 7 no Linux. A interface gráfica e os comandos de rede do Windows não puderam ser executados nesse ambiente.
- **Testado automaticamente (Windows):** pendente até o envio ao GitHub; o workflow executa `-UnitTest` e `-SelfTest` em Windows PowerShell 5.1.
- **Validado no equipamento:** pendente.

## Roteiro de validação no equipamento

1. Abrir o script com o PowerShell padrão, sem administrador; confirmar que a janela abre e a Ethernet é selecionada.
2. Sem cabo: estado SEM LINK. Com cabo: velocidade, IPv4, gateway, DNS e DHCP coerentes com `ipconfig /all`.
3. IPv4 (10 pacotes), DNS, IPv6, MTU e Rastrear rota, com Wi-Fi desligado.
4. Repetir com Wi-Fi conectado: os resultados devem continuar sendo da Ethernet, e a seção de rotas deve indicar qual interface é a preferida.
5. Desconectar e reconectar o cabo com "Acompanhar link" ligado; conferir contagem de mudanças e eventos do driver.
6. Salvar e copiar relatório; confirmar que nenhum outro arquivo foi criado na pasta do script.
7. Repetir em outro computador e em adaptador USB Ethernet.

Nenhum desses testes certifica cabeamento.
