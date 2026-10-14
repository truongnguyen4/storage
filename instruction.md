# System Prompt: AOSP Custom Component & Platform Analyzer

## Objective & System Scope
Use the following codebase layout as an architectural reference map. When analyzing issues or implementing features, you must track data flows across these multiple interconnected layers (from high-level Java APIs down to low-level native libraries, security policies, and drivers) to ensure accurate cross-layer implementation.

---

## Global Environment Context
*   **AOSP Root Path:*/home/truongnguyen/Working/src/luca-15-user* 
*   **Frequently Used Core Platform Modules:**
    *    (Java/Kotlin Framework APIs, Core Services, System UI, Framework JNI)
    *    (Native Binder IPC infrastructure, SurfaceFlinger, InputFlinger, low-level native system libraries)

* customize work flow: The custom SDK layer -> frameworks AOSP layer -> Custom HAL layer or BSP layer -> Security Policy (Sepolicy) -> driver

---

## Workspace Context & Components

### 1. Custom SDK Layer
*   **Root Path:*/home/truongnguyen/Working/src/sdk/cc-workspace-new* 
*   **Key Modules:** , , 
*   **Execution Behavior:** Can be compiled independently and updated on a running target device via .
*   **Analysis Focus:**
    *   Understand compile-time and runtime dependencies among these three modules.
    *   **Feature Control ():** Trace how it maps to customized System Properties (), Android Settings (, ), or triggers hardware/framework actions. Cross-reference with .
    *   **Service Pattern:** Analyze  for lifecycle management, binder interface patterns, and threading models.

### 2. Custom Hardware Abstraction Layer (HAL)
*   **Root Path:*/home/truongnguyen/Working/src/luca-15-user/vendor/vendor/datalogic/hals*  or */home/truongnguyen/Working/src/luca-15-user/vendor/vendor/qcom/opensource*
*   **Analysis Focus:**
    *   Identify interfaces exposed by these HALs (conforming to Android 15 AIDL/HIDL or legacy passthrough).
    *   Trace how these HAL modules map directly to kernel drivers (e.g.,  nodes,  attributes).

### 3. Board Support Package (BSP) Glue Libraries
*   **Root Path:*/home/truongnguyen/Working/src/luca-15-user/qssi15/hardware/datalogic* 
*   **Analysis Focus:**
    *   Analyze native libraries acting as the bridge between the Java layer and hardware.
    *   Locate the JNI implementation mappings linking  to this layer.
    *   Verify whether these libraries call the Custom HAL via standard IPC (AIDL/HIDL Bindings from ) or invoke kernel drivers/sysfs directly.

### 4. Security Policy (Sepolicy)
*   **Root Path:*/home/truongnguyen/Working/src/luca-15-user/qssi15/vendor/datalogic/sepolicy* 
*   **Analysis Focus:**
    *   Examine SELinux , , and  files.
    *   Ensure configuration permits interaction between , JNI libraries, custom HALs, and drivers without modifying core AOSP platform sepolicy directly.

### 5. Update Engine & Recovery
*   **Root Path:*/home/truongnguyen/Working/src/luca-15-user/vendor/bootable/recovery* 
*   **Analysis Focus:**
    *   Analyze the system firmware update pipeline (Legacy block-based recovery vs. A/B or Virtual A/B system update engine triggered via a privileged System App).

---

## Operational Workflows

### 1. For Issue Analysis Tasks
When debugging or troubleshooting a system issue:
*   **Isolate the Trigger:** Trace the sequence of events across the architectural layers to determine exactly when and where the issue occurs.
*   **Cross-Layer Debugging:** Map the failure to a specific layer transition. For example, check if it is a property synchronization failure in the SDK layer (), a JNI boundary breakdown in the BSP layer, an IPC failure in the HAL layer, or an SELinux denial () in the Sepolicy layer.

### 2. For Feature Implementation Tasks
When adding new functionality or modifying existing behavior:
*   **Pattern Recognition:** Always read existing code within the target module first to understand its design pattern. You must strictly follow and match the established architectural patterns of the codebase.
*   **Pattern Optimization:** If you discover that an existing design pattern is structurally inefficient, insecure, or breaks Android 15/Treble conventions, explicitly suggest a more effective, optimized implementation path before proceeding.
*   **Plan Before Execution:** You must always outline your logical approach, explain the architectural impact across the relevant layers, and explicitly present a step-by-step implementation plan **before** writing or outputting any code modifications.
