using UnityEngine;

public class AdditionalLightShadowController : MonoBehaviour
{
    [Tooltip("是否让这个光源透射阴影")]
    public bool castShadows = true;

    [Tooltip("阴影类型")]
    public LightShadows shadowType = LightShadows.Soft;

    private Light targetLight;

    void Start()
    {
        targetLight = GetComponent<Light>();

        if (targetLight == null)
        {
            Debug.LogError("当前GameObject上没有Light组件");
            return;
        }

        ApplyShadowSettings();
    }

    // 新增方法，在Inspector里修改数值时，编辑器会立刻调用它
    private void OnValidate()
    {
        if(targetLight == null)
            targetLight = GetComponent<Light>();

        if(targetLight != null)
            ApplyShadowSettings();
    }
    void ApplyShadowSettings()
    {
        if (castShadows)
        {
            targetLight.shadows = shadowType;
            Debug.Log($"[{gameObject.name}] 阴影已启用：{shadowType}");
        }
        else
        {
            targetLight.shadows = LightShadows.None;
            Debug.Log($"[{gameObject.name}] 阴影已禁用");
        }
    }
}