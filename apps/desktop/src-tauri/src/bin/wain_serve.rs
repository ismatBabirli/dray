//! `wain-serve [--port N | --version]`: Wain's core with no window. See
//! SERVE-PLAN.md.

const DEFAULT_PORT: u16 = wain_proto::SERVE_PORT;

#[tokio::main]
async fn main() {
    // What `wain update` compares the installer's pick against, since beside
    // the Mac app the `wain` next to this one no longer says what it is.
    if std::env::args().nth(1).as_deref() == Some("--version") {
        println!("wain-serve {}", option_env!("WAIN_CLI_VERSION").unwrap_or("dev"));
        return;
    }
    let mut args = std::env::args().skip(1);
    let mut port = DEFAULT_PORT;
    while let Some(arg) = args.next() {
        match (arg.as_str(), args.next().map(|v| v.parse())) {
            ("--port", Some(Ok(p))) => port = p,
            _ => {
                eprintln!("usage: wain-serve [--port N]   (default {DEFAULT_PORT}; 0 picks one)");
                std::process::exit(2);
            }
        }
    }

    ade_lib::analytics::install_panic_hook();
    if let Err(e) = ade_lib::serve::run(port).await {
        eprintln!("wain-serve: {e:#}");
        std::process::exit(1);
    }
}
