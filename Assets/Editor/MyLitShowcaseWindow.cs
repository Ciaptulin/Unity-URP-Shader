using UnityEditor;
using UnityEngine;

/// <summary>
/// MyLit 展示窗口：自动绕物体转相机 + 循环扫描材质 float 属性。
/// 打开：菜单栏 Tools > MyLit Showcase Window
/// 配合 Unity Recorder 可一键出展示视频。
/// </summary>
public class MyLitShowcaseWindow : EditorWindow
{
    // ---- 转台 ----
    Transform orbitTarget;
    Transform cameraTransform;
    float orbitSpeedDeg = 20f;   // 度/秒
    float orbitRadius = 3f;
    float orbitHeight = 1.5f;
    bool orbitEnabled = true;

    // ---- 参数扫描 ----
    Renderer paramTarget;
    string propertyName = "_Metalness";
    float valueMin = 0f;
    float valueMax = 1f;
    float cycleSeconds = 4f;
    bool sweepEnabled = true;

    double startTime;
    bool running;

    // 参数扫描用：记录原始值，Stop 时恢复
    float originalValue;
    bool hasOriginalValue;

    // 转台用：记录相机原始位姿，Stop 时恢复
    Vector3 originalCamPos;
    Quaternion originalCamRot;
    bool hasOriginalCam;

    // 转台起始角（弧度）：Start 时取当前相机相对目标的水平角，实现平滑起转
    float orbitStartAngleRad;
    // 转台起始朝向：Start 时的相机 rotation，绕 Y 轴公转时保持相对朝向
    Quaternion orbitStartRot;

    [MenuItem("Tools/MyLit Showcase Window")]
    static void Open()
    {
        GetWindow<MyLitShowcaseWindow>("MyLit Showcase");
    }

    void OnEnable()
    {
        AutoAssignDefaults();
    }

    /// <summary>
    /// 自动填充默认引用：Main Camera + 场景中的角色（优先名字含"荧"）。
    /// 只在引用为空时填充，不会覆盖你手动拖的。
    /// </summary>
    void AutoAssignDefaults()
    {
        if (cameraTransform == null)
        {
            var cam = Camera.main;
            if (cam != null) cameraTransform = cam.transform;
        }

        if (orbitTarget == null)
        {
            orbitTarget = FindCharacterTransform();
        }
    }

    Transform FindCharacterTransform()
    {
        // 1. 名字含"荧"的物体
        var all = Object.FindObjectsByType<Transform>(FindObjectsSortMode.None);
        foreach (var t in all)
        {
            if (t.name.Contains("荧")) return t;
        }
        // 2. 退化：任意带 SkinnedMeshRenderer 的物体（角色通常有）
        var smrs = Object.FindObjectsByType<SkinnedMeshRenderer>(FindObjectsSortMode.None);
        if (smrs.Length > 0) return smrs[0].transform;
        return null;
    }

    void OnDisable()
    {
        Stop();
    }

    void OnGUI()
    {
        if (GUILayout.Button("自动查找默认引用 (Main Camera + 女主角)"))
        {
            AutoAssignDefaults();
        }
        EditorGUILayout.Space();

        EditorGUILayout.LabelField("转台 (Orbit)", EditorStyles.boldLabel);
        orbitEnabled = EditorGUILayout.Toggle("启用转台", orbitEnabled);
        using (new EditorGUI.DisabledScope(!orbitEnabled))
        {
            orbitTarget = (Transform)EditorGUILayout.ObjectField("Orbit Target", orbitTarget, typeof(Transform), true);
            cameraTransform = (Transform)EditorGUILayout.ObjectField("Camera Transform", cameraTransform, typeof(Transform), true);
            orbitSpeedDeg = EditorGUILayout.FloatField("速度 (度/秒)", orbitSpeedDeg);
            orbitRadius = EditorGUILayout.FloatField("半径", orbitRadius);
            orbitHeight = EditorGUILayout.FloatField("高度", orbitHeight);
        }

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("参数扫描 (Parameter Sweep)", EditorStyles.boldLabel);
        sweepEnabled = EditorGUILayout.Toggle("启用参数扫描", sweepEnabled);
        using (new EditorGUI.DisabledScope(!sweepEnabled))
        {
            paramTarget = (Renderer)EditorGUILayout.ObjectField("Param Target (Renderer)", paramTarget, typeof(Renderer), true);
            propertyName = EditorGUILayout.TextField("Property Name", propertyName);
            valueMin = EditorGUILayout.FloatField("Min", valueMin);
            valueMax = EditorGUILayout.FloatField("Max", valueMax);
            cycleSeconds = EditorGUILayout.FloatField("Cycle (秒)", cycleSeconds);
            EditorGUILayout.HelpBox("提示：只支持 float 属性，如 _Metalness / _Smoothness。\nshader 关键字(_NORMALMAP 等)需在材质 Inspector 手动开关。", MessageType.Info);
        }

        EditorGUILayout.Space();
        if (GUILayout.Button(running ? "Stop" : "Start", GUILayout.Height(30)))
        {
            if (running) Stop(); else Start();
        }

        if (running)
        {
            EditorGUILayout.LabelField("运行中…", EditorStyles.boldLabel);
        }
    }

    void Start()
    {
        startTime = EditorApplication.timeSinceStartup;
        running = true;

        Debug.Log($"[MyLitShowcase] Start. orbitEnabled={orbitEnabled}, orbitTarget={(orbitTarget==null?"null":orbitTarget.name)}, cameraTransform={(cameraTransform==null?"null":cameraTransform.name)}, sweepEnabled={sweepEnabled}, paramTarget={(paramTarget==null?"null":paramTarget.name)}");

        // 记录参数扫描目标材质的原始值，Stop 时恢复
        if (sweepEnabled && paramTarget != null && !string.IsNullOrEmpty(propertyName))
        {
            var mat = paramTarget.sharedMaterial;
            if (mat != null && mat.HasProperty(propertyName))
            {
                originalValue = mat.GetFloat(propertyName);
                hasOriginalValue = true;
            }
        }

        // 记录相机原始位姿，Stop 时恢复
        if (orbitEnabled && cameraTransform != null)
        {
            originalCamPos = cameraTransform.position;
            originalCamRot = cameraTransform.rotation;
            hasOriginalCam = true;

            // 以当前相机位姿为基准：记录水平角、水平半径、高度、朝向
            if (orbitTarget != null)
            {
                Vector3 dir = originalCamPos - orbitTarget.position;
                orbitStartAngleRad = Mathf.Atan2(dir.x, dir.z);
                orbitRadius = new Vector2(dir.x, dir.z).magnitude;
                orbitHeight = dir.y;                // 用当前实际高度，不用面板值
                orbitStartRot = originalCamRot;     // 用当前朝向
            }
            else
            {
                orbitStartAngleRad = 0f;
                orbitStartRot = originalCamRot;
            }
        }

        EditorApplication.update += Tick;
    }

    void Stop()
    {
        running = false;
        EditorApplication.update -= Tick;

        // 恢复原始值（避免污染材质资产）
        if (hasOriginalValue && paramTarget != null && !string.IsNullOrEmpty(propertyName))
        {
            var mat = paramTarget.sharedMaterial;
            if (mat != null && mat.HasProperty(propertyName))
            {
                mat.SetFloat(propertyName, originalValue);
            }
            hasOriginalValue = false;
        }

        // 恢复相机原始位姿
        if (hasOriginalCam && cameraTransform != null)
        {
            cameraTransform.position = originalCamPos;
            cameraTransform.rotation = originalCamRot;
            hasOriginalCam = false;
        }
    }

    int tickCount = 0;

    void Tick()
    {
        if (!running) return;
        double t = EditorApplication.timeSinceStartup - startTime;

        tickCount++;
        if (tickCount % 120 == 1)
            Debug.Log($"[MyLitShowcase] Tick #{tickCount}, t={t:F2}s");

        // 转台：以 Start 时记录的位姿为基准，绕竖直轴做刚体公转
        // 位置绕目标旋转，朝向同步绕 Y 轴旋转，完整保留你摆放的视角关系
        if (orbitEnabled && orbitTarget != null && cameraTransform != null)
        {
            float deltaDeg = (float)(t * orbitSpeedDeg);
            float rad = orbitStartAngleRad + deltaDeg * Mathf.Deg2Rad;
            Vector3 pos = orbitTarget.position
                        + new Vector3(Mathf.Sin(rad) * orbitRadius, orbitHeight, Mathf.Cos(rad) * orbitRadius);
            cameraTransform.position = pos;
            cameraTransform.rotation = Quaternion.AngleAxis(deltaDeg, Vector3.up) * orbitStartRot;
        }

        // 参数扫描（PingPong 来回）
        // 注意：URP + SRP Batcher 下 MaterialPropertyBlock 对 per-material 属性不生效，
        // 因此直接改材质实例，Stop 时恢复原值。
        if (sweepEnabled && paramTarget != null && cycleSeconds > 0.01f && !string.IsNullOrEmpty(propertyName))
        {
            float phase = (float)((t % cycleSeconds) / cycleSeconds);
            float v = Mathf.Lerp(valueMin, valueMax, Mathf.PingPong(phase * 2f, 1f));

            var mat = paramTarget.sharedMaterial;
            if (mat != null && mat.HasProperty(propertyName))
            {
                mat.SetFloat(propertyName, v);
            }
        }

        SceneView.RepaintAll();
        Repaint();
    }
}
