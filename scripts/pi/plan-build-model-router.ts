import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const PLAN_STATE_ENTRY = "plan-mode-state";
const PLAN_MODEL = { provider: "opencode-go", id: "kimi-k3" } as const;
const BUILD_MODEL = { provider: "opencode-go", id: "deepseek-v4-flash" } as const;
const STATUS_KEY = "plan-build-model";

type PlanModeStateEntry = {
	type?: string;
	customType?: string;
	data?: { enabled?: boolean };
};

export default function planBuildModelRouter(pi: ExtensionAPI) {
	async function selectModel(ctx: ExtensionContext, requestedTarget?: typeof PLAN_MODEL | typeof BUILD_MODEL) {
		const target = requestedTarget ?? (planModeEnabled(ctx, pi) ? PLAN_MODEL : BUILD_MODEL);
		if (ctx.model?.provider === target.provider && ctx.model.id === target.id) {
			updateStatus(ctx, target.id);
			return;
		}

		const model = ctx.modelRegistry
			.getAll()
			.find((candidate) => candidate.provider === target.provider && candidate.id === target.id);
		if (!model) {
			ctx.ui.notify(`Model unavailable: ${target.provider}/${target.id}`, "error");
			return;
		}

		const selected = await pi.setModel(model);
		if (!selected) {
			ctx.ui.notify(`No authentication for ${target.provider}/${target.id}`, "error");
			return;
		}
		updateStatus(ctx, target.id);
	}

	pi.on("session_start", async (_event, ctx) => {
		await selectModel(ctx);
	});

	pi.on("input", async (event, ctx) => {
		const target = targetForPlanCommand(event.text);
		if (target) await selectModel(ctx, target);
	});

	pi.on("before_agent_start", async (_event, ctx) => {
		await selectModel(ctx);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		ctx.ui.setStatus(STATUS_KEY, undefined);
	});
}

function planModeEnabled(ctx: ExtensionContext, pi: ExtensionAPI) {
	const entries = ctx.sessionManager.getBranch() as PlanModeStateEntry[];
	for (let index = entries.length - 1; index >= 0; index -= 1) {
		const entry = entries[index];
		if (entry?.type === "custom" && entry.customType === PLAN_STATE_ENTRY) {
			return entry.data?.enabled === true;
		}
	}
	return pi.getFlag("plan") === true;
}

function targetForPlanCommand(input: string) {
	const command = input.trim().toLowerCase();
	if (!command.startsWith("/plan")) return undefined;
	if (/^\/plan\s+(implement|exit|off)(?:\s|$)/.test(command)) return BUILD_MODEL;
	return PLAN_MODEL;
}

function updateStatus(ctx: ExtensionContext, modelId: string) {
	ctx.ui.setStatus(STATUS_KEY, `model: ${modelId}`);
}
