Shader "Hidden/Shader/OutlinePass"
{
    HLSLINCLUDE

    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/NormalBuffer.hlsl"

    TEXTURE2D_X(OutlineBuffer);
    float4 OutlineColor;
    float2 TexelSize;
    float Threshold;
    int Thickness;
    float OutlineIntensity;

    #define v2 1.41421
    #define c45 0.707107
    #define c225 0.9238795
    #define s225 0.3826834

    #define SEAM_EPSILON 1e-4
    #define MaxSamples 8
    // Neighbour pixel positions
    static float2 SamplePoints[MaxSamples] =
    {
        float2( 1,  1),
        float2( 0,  1),
        float2(-1,  1),
        float2(-1,  0),
        float2(-1, -1),
        float2( 0, -1),
        float2( 1, -1),
        float2( 1, 0),
    };

    static float2 BlurPoints[5] =
    {
        float2(1,0),
        float2(0,1),
        float2(1,0),
        float2(0,1),
        float2(1,1)
    };

    float GaussSamples[32];

    float SampleTexture(float2 UV)
    {
        return SAMPLE_TEXTURE2D_X_LOD(OutlineBuffer,s_linear_clamp_sampler,UV,0);
    }

    float4 FullScreenPass(Varyings Input) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(Varyings);

        float2 UV = Input.positionCS * _ScreenSize.zw * _RTHandleScale.xy;
        float4 Outline = SAMPLE_TEXTURE2D_X_LOD(OutlineBuffer, s_linear_clamp_sampler, UV, 0);
        Outline.a = 0;

        if (Luminance(Outline.rgb) < Threshold)
        {
            float currentDepth = LoadCameraDepth((uint2)Input.positionCS.xy);

            for (int i = 0; i < MaxSamples; i++)
            {
                for(int j = 1; j <= Thickness; j++)
                {

                    float2 UVN = UV + _ScreenSize.zw * _RTHandleScale.xy * SamplePoints[i] * j;
                    float4 Neighbour = SAMPLE_TEXTURE2D_X_LOD(OutlineBuffer, s_linear_clamp_sampler, UVN, 0);


                    if (Luminance(Neighbour) > Threshold)
                    {
                        uint2 neighbourPx = (uint2)(Input.positionCS.xy + SamplePoints[i] * j);
                        float neighbourDepth = LoadCameraDepth(neighbourPx);

                        if (currentDepth > neighbourDepth + SEAM_EPSILON)
                            continue;

                        Outline.rgb = OutlineColor.rgb;
                        Outline.a = 1;
                        break;
                    }
                }
            }
        }

        return Outline;
    }

    ENDHLSL

    SubShader
    {
        Pass
        {
            Name "Custom Pass 0"

            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FullScreenPass
            ENDHLSL
        }

        Pass
        {
            Name "Outline Mask"

            ZWrite Off
            ZTest Always
            Blend Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex VertMask
            #pragma fragment FragMask

            #define DEPTH_EPSILON 1e-5

            struct AttributesMask
            {
                float3 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct VaryingsMask
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            VaryingsMask VertMask(AttributesMask input)
            {
                VaryingsMask output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = TransformObjectToHClip(input.positionOS);
                return output;
            }

            float4 FragMask(VaryingsMask input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                uint2 px = (uint2)input.positionCS.xy;
                float sceneDepth = LoadCameraDepth(px);
                float fragDepth = input.positionCS.z;
                if (fragDepth < sceneDepth - DEPTH_EPSILON) discard;
                return float4(1, 1, 1, 1);
            }
            ENDHLSL
        }
    }
    Fallback Off
}
