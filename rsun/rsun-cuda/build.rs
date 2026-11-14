fn main() {
    println!("cargo:rerun-if-changed=src/kernels/horizon.cu");
    println!("cargo:rerun-if-changed=src/kernels/radiation.cu");
}
