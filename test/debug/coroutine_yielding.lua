local cqueues = require("cqueues")

local cq = cqueues.new()
local completed = 0
local num = 5

print("Iniciando Teste de Yield Puro (cqueues)...")
local start = cqueues.monotime()

for i = 1, num do
    cq:wrap(function()
        print(string.format("[%d] Yielding...", i))
        cqueues.sleep(1) -- Deve liberar para as outras coroutines
        print(string.format("[%d] Acordou!", i))
        completed = completed + 1
    end)
end

cq:loop()
local duration = cqueues.monotime() - start
print(string.format("Tempo total para %d sleeps de 1s: %.2f segundos", num, duration))

if duration < 1.5 then
    print("\n✅ O agendador está cooperativo.")
else
    print("\n❌ O agendador está bloqueante.")
end
