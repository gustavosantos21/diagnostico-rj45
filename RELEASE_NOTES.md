# Diagnóstico RJ45 1.1.0 — Portátil

Código aberto sob a Unlicense, sem cobrança, ativação ou chave de licença. Permite modificação e redistribuição, inclusive comercialmente. Veja LICENSE no repositório para a declaração completa. Esta declaração também cobre a versão 1.0.0 anterior.

Baixe somente **DiagnosticoRJ45.exe** e execute em uma pasta ou pendrive. Não requer instalação, arquivos de configuração ou pasta de logs. Os resultados ficam em memória; exportar relatório é opcional.

Os modos de verificação também não geram arquivos. Não há extração de componentes em pasta temporária. Usa .NET Framework 4.8 e APIs nativas do Windows, sem iniciar PowerShell ou ping. O manifesto usa os privilégios atuais do usuário, sem pedir elevação.

Inclui link, velocidade, MAC, IPv4, máscara, IPv6, gateway, DNS, sufixo DNS, DHCP e validade da concessão, quando disponíveis. O teste ICMP informa latência mínima/média/máxima, valida a rota no adaptador e usa endereço de origem explícito. Links de 100 Mb/s são apresentados como característica observada. O perfil inicial é Intel I219-LM; outros adaptadores usam a enumeração padrão do Windows.

Executável sem assinatura digital, sujeito às políticas corporativas de execução. A validação completa da interface e dos testes dentro do aplicativo continua pendente de liberação. Os testes manuais pelas ferramentas do Windows já confirmaram, neste notebook, link a 100 Mb/s e comunicação com o gateway; isso não certifica o cabo.

Não mede mapa de fios, comprimento, PoE ou distância até falhas.
