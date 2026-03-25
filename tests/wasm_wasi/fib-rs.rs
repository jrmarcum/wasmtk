use std::env;

fn fib(n: u32) -> u32 {
    match n {
        0 => 0,
        1 => 1,
        _ => fib(n - 1) + fib(n - 2),
    }
}

fn main() {
    // Get args from the WASI environment
    let args: Vec<String> = env::args().collect();
    
    // args[0] is the program name
    // args[1] is our target number
    if let Some(arg) = args.get(1) {
        if let Ok(n) = arg.parse::<u32>() {
            println!("Calculating Fib for {}: {}", n, fib(n));
        } else {
            println!("Please provide a valid number.");
        }
    } else {
        println!("No argument provided. Defaulting to 10: {}", fib(10));
    }
}