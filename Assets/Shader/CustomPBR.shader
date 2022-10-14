Shader "Missnish/CustomPBR"
{
    Properties
    {
        _MainTex ("Albedo", 2D) = "white" {}
        _Metallic ("Metallic", 2D) = "white" {}
        _Roughness ("Roughness", Range(0, 1)) = 0
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
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 pos : SV_POSITION;
                float3 normal : TEXCOORD1;
                float3 posWS : TEXCOORD2;
                
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _Metallic;
            float _Roughness;
            
            
            //-----------------------Vertex Shader-----------------------
            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = mul(unity_ObjectToWorld, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            //-----------------------Custom Function-----------------------
            //法线分布函数
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

            //几何遮蔽函数
            float Geometry(float NdotL, float NdotV, float roughness, float k)
            {
                //几何障碍(Geometry Obstruction): 从视角观察方向看过去的微表面互相遮挡
                float viewG = NdotV / lerp(NdotV, 1.0, k);
                //几何阴影(Geometry Shadowing): 从光线反射方向所产生的的微表面互相遮挡
                float lightG = NdotL / lerp(NdotL, 1.0, k);

                float resultG = lightG * viewG;
                return resultG;
            }

            //菲涅尔方程
            float3 Fresnel(float HdotV, float3 F0)
            {
                float3 resultF = F0 + (1.0 - F0) * pow(1.0 - HdotV, 5);
                return resultF;
            }


            //-----------------------Fragment Shader-----------------------
            fixed4 frag (v2f i) : SV_Target
            {
                //数据准备
                float3 normalDir = normalize(i.normal);
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.posWS.xyz);
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                float3 halfDir = normalize(viewDir + lightDir);
                float3 lightColor = _LightColor0.rgb;

                float3 baseColor = tex2D(_MainTex, i.uv);
                float roughness = _Roughness;
                float metalness = tex2D(_Metallic, i.uv);

                float NdotH = max(0.00001, dot(normalDir, halfDir));
                float NdotL = max(0.00001, dot(normalDir, lightDir));       //入射方向即光线方向: ωi - lightDir
                float NdotV = max(0.00001, dot(normalDir, viewDir));        //出射方向即观察方向: ωo - viewDir
                float HdotV = max(0.00001, dot(halfDir, viewDir));


                //Direct: Specular
                float directD = NormalDistribution(NdotH, roughness);
                float3 F0 = lerp(float3(0.04, 0.04, 0.04), baseColor, metalness);
                float3 directF = Fresnel(HdotV, F0);
                float directG = Geometry(NdotL, NdotV, roughness, kDirect(roughness));

                float3 directSpecularBRDF = (directD * directF * directG) / (4 * NdotL * NdotV);     //镜面反射BRDF
                float3 lightEnergy = lightColor * NdotL;                                             //受光程度

                float3 directSpecular = directSpecularBRDF * lightEnergy;                                //直接光 - 镜面反射结果

                //Direct: Diffuse
                float kDiffuse = (1.0 - directF) * (1.0 - metalness);
                float3 directDiffuseBRDF = kDiffuse * baseColor;                                     //漫反射BRDF
                float3 directDiffuse = directDiffuseBRDF * lightEnergy;                                  //直接光 - 漫反射结果
                
                //Indirect: Specular - CubeMap


                //Indirect: Diffuse - 球谐系数(SH); Light Probe


                float3 finalRGB = directSpecular + directDiffuse;
                return float4(finalRGB,1.0);
            }



            ENDCG
        }
    }
}
