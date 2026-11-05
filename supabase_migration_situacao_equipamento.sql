-- Adiciona coluna situacao_equipamento na tabela os_folders
-- Valores possíveis: 'em_analise' | 'aguardando_pecas' | 'aguardando_orcamento' | NULL
ALTER TABLE public.os_folders
  ADD COLUMN IF NOT EXISTS situacao_equipamento TEXT
  CHECK (situacao_equipamento IS NULL OR situacao_equipamento IN ('em_analise', 'aguardando_pecas', 'aguardando_orcamento'));

COMMENT ON COLUMN public.os_folders.situacao_equipamento IS
  'Situação do equipamento quando a OS está em execução: em_analise | aguardando_pecas | aguardando_orcamento';
