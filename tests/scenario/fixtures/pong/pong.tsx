import { Read, Show } from "helder/view";

export const W = 480, H = 320, PADDLE = 128, BALL = 10, WIN = 7;

export type State = { ball: { x: number; y: number }; left: number; right: number; score: number[]; over: boolean; paused: boolean };

export function serve(): State {
	return { ball: { x: W / 2 - BALL / 2, y: H / 2 - BALL / 2 }, left: H / 2 - PADDLE / 2, right: H / 2 - PADDLE / 2, score: [0, 0], over: false, paused: false };
}

// the court as a state draws it: posed by the stories, run by the game
export function Court(props: { state: Read<State> }) {
	return <view width={W} height={H} background="#0e1424" overflow="hidden">
		<view position="absolute" left={W / 2 - 1} top={0} width={2} height={H} background="#26304a"/>
		<view position="absolute" left={16} top={props.state().left} width={8} height={PADDLE} radius={4} background="#9fd3ff"/>
		<view position="absolute" left={W - 24} top={props.state().right} width={8} height={PADDLE} radius={4} background="#f2c65a"/>
		<view position="absolute" left={props.state().ball.x} top={props.state().ball.y} width={BALL} height={BALL} radius={BALL / 2} background="#e8e2d0"/>
		<view position="absolute" left={0} right={0} top={12} align-items="center">
			<text font-size={24} font-weight={700} color="#e8e2d0">{`${props.state().score[0]}   ${props.state().score[1]}`}</text>
		</view>
		<Show when={() => props.state().paused && !props.state().over}>
			<view position="absolute" left={0} right={0} top={0} bottom={0} align-items="center" justify="center" gap={8} background="#0e1424cc">
				<text font-size={28} font-weight={700} color="#e8e2d0">Paused</text>
				<text font-size={13} color="#8a93a8">Press P or Esc to resume</text>
			</view>
		</Show>
		<Show when={() => props.state().over}>
			<view position="absolute" left={0} right={0} top={0} bottom={0} align-items="center" justify="center" gap={8} background="#0e1424cc">
				<text font-size={28} font-weight={700} color={props.state().score[0] > props.state().score[1] ? "#9fd3ff" : "#f2c65a"}>{props.state().score[0] > props.state().score[1] ? "You win!" : "You lose"}</text>
				<text font-size={13} color="#8a93a8">Press space to play again</text>
			</view>
		</Show>
	</view>;
}
