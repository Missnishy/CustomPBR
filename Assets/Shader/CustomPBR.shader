Shader "Missnish/CustomPBR"
{
    Properties
    {
        _Color("Color", Color) = (1.0, 1.0, 1.0)
        _MainTex ("Albedo", 2D) = "white" {}
        _MetallicTex ("Metallic", 2D) = "white" {}
        _Roughness ("Roughness", Range(0, 1)) = 0
        _NormalTex("Normal", 2D) = "bump"{}
        _NormalIntensity("Normal Intensity", float) = 1.0
        _AOTex("Ambient Occlusion", 2D) = "white"{}
        _AOIntensity("Ambient Occlusion Intensity", Range(0, 1)) = 1.0
        _CubeMap("CubeMap", Cube) = "white"{}
        _CubeMapIntensity("CubeMap Light Intensity", float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag


            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 pos : SV_POSITION;
                float3 posWS : TEXCOORD1;
                float3 normal : TEXCOORD2;
                float3 tangent : TEXCOORD3;
                float3 binormal : TEXCOORD4;
                
            };

            float3 _Color;
            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _MetallicTex;
            float _Roughness;
            sampler2D _NormalTex;
            sampler2D _AOTex;
            samplerCUBE _CubeMap;
            float4 _CubeMap_HDR;
            float _AOIntensity;
            float _CubeMapIntensity;
            float _NormalIntensity;
            
            
            //-----------------------Vertex Shader-----------------------
            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = mul(unity_ObjectToWorld, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.tangent = normalize(mul(unity_ObjectToWorld, v.tangent).xyz);
                //v.tangent.w???tangent??????????????????????????????????????????????????????????????????
                o.binormal = cross(o.normal, o.tangent) * v.tangent.w;

                return o;
            }

            //-----------------------Custom Function-----------------------
            //??????????????????
            float NormalDistribution(float NdotH, float roughness)
            {
                float squareRough = roughness * roughness;
                float squareDot = NdotH * NdotH;

                float resultD = squareRough / (UNITY_PI * (squareDot * (squareRough - 1.0) + 1.0) * (squareDot * (squareRough - 1.0) + 1.0));
                return resultD;
            }

            float kDirect(float roughness)
            {
                return ((roughness + 1.0) * (roughness + 1.0)) / 8.0;
            }

            float kIBL(float roughness)
            {
                return roughness * roughness / 2.0;
            }

            //??????????????????
            float Geometry(float NdotL, float NdotV, float roughness, float k)
            {
                //????????????(Geometry Obstruction): ??????????????????????????????????????????????????????
                float viewG = NdotV / lerp(NdotV, 1.0, k);
                //????????????(Geometry Shadowing): ?????????????????????????????????????????????????????????
                float lightG = NdotL / lerp(NdotL, 1.0, k);

                float resultG = lightG * viewG;
                return resultG;
            }

            //???????????????
            float3 Fresnel(float NdotV, float3 F0)
            {
                float3 resultF = F0 + (1.0 - F0) * pow(1.0 - NdotV, 5);
                return resultF;
            }


            //-----------------------Fragment Shader-----------------------
            fixed4 frag (v2f i) : SV_Target
            {
                //????????????
                float4 normalMap = (tex2D(_NormalTex, i.uv));
                float3 normalData = UnpackNormal(normalMap);          //?????????????????????????????????????????????????????????[0,1]?????????[-1,1]
                normalData.xy *= _NormalIntensity;
                float3x3 TBN = float3x3(i.tangent, i.binormal, i.normal);
                float3 normalDir = normalize(mul(normalData.xyz, TBN));
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.posWS.xyz);
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                float3 halfDir = normalize(viewDir + lightDir);
                float3 reflectDir = normalize(reflect(-viewDir, normalDir));

                float3 lightColor = _LightColor0.rgb;
                //float3 baseColor = _Color * tex2D(_MainTex, i.uv);
                float3 baseColor = _Color * pow(tex2D(_MainTex, i.uv), 2.2);
                float roughness = _Roughness;
                float metalness = tex2D(_MetallicTex, i.uv);
                float aoMap = tex2D(_AOTex, i.uv);    
                float ao = lerp(1, aoMap, _AOIntensity);

                float NdotH = max(0.00001, dot(normalDir, halfDir));
                float NdotL = max(0.00001, dot(normalDir, lightDir));       //???????????????????????????: ??i - lightDir
                float NdotV = max(0.00001, dot(normalDir, viewDir));        //???????????????????????????: ??o - viewDir

                //Direct: Specular
                float NDF = NormalDistribution(NdotH, roughness);
                float3 F0 = lerp(float3(0.04, 0.04, 0.04), baseColor, metalness);
                float3 ks = Fresnel(NdotV, F0);
                float directG = Geometry(NdotL, NdotV, roughness, kDirect(roughness));

                float3 directSpecularBRDF = (NDF * ks * directG) / (4 * NdotL * NdotV);            //????????????BRDF
                float3 lightEnergy = lightColor * NdotL;                                           //????????????

                float3 directSpecular = directSpecularBRDF * lightEnergy * UNITY_PI;               //????????? - ??????????????????

                //Direct: Diffuse
                float kd = (1.0 - ks) * (1.0 - metalness);
                float3 directDiffuseBRDF = kd * baseColor;                                           //?????????BRDF
                //float3 directDiffuse = directDiffuseBRDF * lightEnergy;
                float3 directDiffuse = pow(directDiffuseBRDF * lightEnergy, 1 / 2.2);                //????????? - ???????????????
                
                //Indirect: Specular - CubeMap Specular; Reflection Probe
                float roughnessSmooth = roughness * (1.7 - 0.7 * roughness);            //?????????????????????
                half mipLevel = roughness * 6.0;                                        //6 - PBR???????????????MipMap??????
                float4 cubeMapSpecularColor = texCUBE(_CubeMap, float4(reflectDir, mipLevel));
                float3 envLightSpecularEnergy = DecodeHDR(cubeMapSpecularColor, _CubeMap_HDR) * _CubeMapIntensity;
                float indirectG = Geometry(NdotL, NdotV, roughness, kIBL(roughness));
                float3 indirectSpecularBRDF = (NDF * ks * indirectG) / (4 * NdotL * NdotV);
                float3 indirectSpecular = indirectSpecularBRDF * envLightSpecularEnergy;

                //Indirect: Diffuse - CubeMap Diffuse; ????????????(SH); Light Probe
                float4 cubeMapDiffuseColor = texCUBElod(_CubeMap, float4(normalDir, mipLevel));                     //?????????: ???NormalDir??????CubeMap???Diffuse
                float3 envLightDiffuseEnergy = DecodeHDR(cubeMapDiffuseColor, _CubeMap_HDR) * _CubeMapIntensity;
                //float3 envLightDiffuseEnergySH = ShadeSH9(float4(normalDir, 1.0));                                //?????????: ????????????
                float3 indirectDiffuse = pow(kd * baseColor * envLightDiffuseEnergy, 1 / 2.2);

                float3 finalRGB = (directSpecular + directDiffuse + indirectSpecular + indirectDiffuse) * ao;
                return float4(finalRGB,1.0);
            }



            ENDCG
        }
    }
}
