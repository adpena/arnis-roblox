use arbx_roblox_export::build_sample_manifest;

fn main() {
    let json = build_sample_manifest().to_json_pretty();
    println!("{json}");
}
