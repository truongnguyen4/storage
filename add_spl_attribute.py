import xml.etree.ElementTree as ET

# List of specific project names to update
target_names = [
    "platform/external/sqlite",
    "platform/packages/services/Telecomm",
    "platform/external/skia",
    "platform/frameworks/opt/telephony",
    "platform/packages/services/Mms",
    "platform/packages/services/Telephony",
    "platform/external/libjpeg-turbo",
    "platform/packages/apps/Launcher3",
    "platform/frameworks/native",
    "platform/cts",
    "platform/packages/apps/CertInstaller",
    "platform/frameworks/base",
    "platform/external/dng_sdk",
    "platform/packages/apps/Settings",
]

xml_file = "/home/truongnguyen/Working/src/sx5/.repo/manifests/smr5_sx5.xml"
tree = ET.parse(xml_file)
root = tree.getroot()

for project in root.findall("project"):
    name = project.get("name")
    if name in target_names:
        groups = project.get("groups", "")
        project.set("groups", f"{groups},spl")

tree.write(xml_file, xml_declaration=False, short_empty_elements=False)