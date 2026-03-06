.PHONY: capture judge run clean clean-traces clean-judgments help

SCENARIO ?= character-story-creation
RUNS ?= 1

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

capture: ## Run agent capture (SCENARIO=id RUNS=n)
	bash capture-agent.sh $(SCENARIO) $(RUNS)

capture-all: ## Run agent capture for all scenarios (RUNS=n)
	bash capture-agent.sh all $(RUNS)

capture-manual: ## Run manual capture (RECORDING=file SCENARIO=id)
	bash capture-manual.sh $(RECORDING) $(SCENARIO)

judge: ## Judge a single scenario (SCENARIO=id)
	bash judge.sh $(SCENARIO)

run: ## Run full pipeline: judge all scenarios, produce report
	bash run.sh

clean-traces: ## Delete all captured traces
	rm -rf traces/*/

clean-judgments: ## Delete all judgment outputs
	rm -rf judgments/*/

clean: clean-traces clean-judgments ## Delete all traces and judgments
	@echo "Cleaned."
