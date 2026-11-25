package helder.gfx;

typedef ComputePipelineDesc = {
	// the stage's shader (Stage.Compute), or instead its code (a
	// ComputeShader's pipeline(): Device.createComputePipeline compiles it);
	// its ShaderCode.workgroupSize is the workgroup's size (Metal's
	// dispatches give it)
	?shader:ShaderModule,
	?program:ShaderCode
}
