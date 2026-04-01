fn main() {
    // Re-run build if CUDA kernel source changes
    println!("cargo:rerun-if-changed=src/kernels/horizon.cu");
}
