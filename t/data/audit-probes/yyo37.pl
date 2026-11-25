use Sys::Hostname; print length(hostname()) > 0 ? "host" : "none", "\n";
