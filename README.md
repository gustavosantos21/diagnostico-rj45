# Diagnóstico RJ45 1.0.1 — Portátil

Ferramenta de diagnóstico Ethernet para Windows, com perfil inicial para HP EliteBook 640 G11 e Intel I219-LM. Outros computadores usam a enumeração padrão de placas Ethernet físicas do Windows.

## Código aberto e uso livre

O código original deste projeto e seus executáveis são disponibilizados sob a [Unlicense](LICENSE), uma dedicação ao domínio público. É permitido usar, copiar, modificar, compilar e distribuir, inclusive comercialmente, sem cobrança, ativação, chave de licença ou obrigação de atribuição. O software é fornecido sem garantia.

Essa declaração se aplica também às versões 1.0.0 e 1.0.1 já publicadas. Os componentes do Windows utilizados mantêm os termos de seus respectivos fornecedores. O projeto não incorpora código, componentes ou assinatura do MobaXterm.

## Portabilidade

Distribuição em **um único `DiagnosticoRJ45.exe`**. Copie para uma pasta ou pendrive e execute. Não tem instalador, configuração externa, banco de dados ou log automático. Os dados ficam em memória e são descartados ao fechar. **Salvar relatório** é opcional e grava somente no local escolhido pelo usuário. Não extrai componentes em uma pasta temporária.

Usa componentes já presentes no Windows compatível (.NET Framework e Windows PowerShell); não inclui runtimes externos. O Windows e os produtos de segurança podem manter seus próprios registros de execução, independentemente do aplicativo. A portabilidade não dispensa as políticas de execução da empresa.

## Uso

Baixe o executável na seção **Releases**. Conecte o cabo a um equipamento de rede ligado, abra o aplicativo e clique em **Atualizar**. Selecione a interface e use **Testar IPv4** para enviar dez pings ao gateway ou a um IPv4 informado. A rota e o endereço de origem são verificados para a Ethernet selecionada.

Exibe link, velocidade negociada, IPv4, gateway, DNS configurado e contadores de erros e tráfego. Permite acompanhar o estado a cada oito segundos e salvar relatório de texto.

## Limitações e validação

Esta versão **não certifica cabeamento** e não mede fios, comprimento, distância até falhas, PoE ou interferência. A velocidade negociada não equivale à taxa real de transferência. Erros e descartes são contadores acumulados do adaptador. O teste ativo requer IPv4; DNS é apenas exibido.

A consulta inicial foi validada na Intel I219-LM, sem cabo conectado. A versão recompilada foi bloqueada por uma política corporativa do Microsoft Defender. Teste ativo com cabo e switch e validação completa da interface continuam pendentes. Compilação e testes automatizados de interpretação não substituem essa validação física. O executável não possui assinatura digital. Em ambiente corporativo, siga o processo de liberação da TI.

## Desenvolvimento

Requisitos: Windows 10/11, .NET Framework 4.8 e Windows PowerShell 5.1 com módulos NetAdapter/NetTCPIP.

```powershell
.\compilar.ps1
$p = Start-Process .\DiagnosticoRJ45.exe -ArgumentList '--unit-test' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw 'Falha nos testes' }
```

`--unit-test` verifica interpretações e rejeição de destino inválido sem consultar hardware nem enviar pacotes. `--self-test` adiciona consulta local. Ambos retornam código de saída e não criam arquivos. O CI também executa esses modos em uma pasta contendo apenas o EXE e verifica a ausência de arquivos auxiliares nessa pasta. A opção de captura `--preview` foi removida.

## Fluxo de trabalho

- `main` mantém a versão integrada; mudanças seguintes usam branches `feature/...` ou `fix/...` e pull requests. Contribuições devem ser disponibilizadas sob a mesma Unlicense.
- Compilação e verificações automatizadas executam no GitHub Actions em cada push e pull request.
- Versões seguem `MAJOR.MINOR.PATCH`; a versão inicial é **1.0.0**, exibida como **1.0**.
- Tags `v*` geram uma release com o executável compilado no GitHub, sem incluir relatórios da máquina de desenvolvimento.
- Alterações e pendências ficam em [CHANGELOG.md](CHANGELOG.md) e [VALIDACAO.md](VALIDACAO.md).

As instruções de uso detalhadas estão em [LEIA-ME.md](LEIA-ME.md).
