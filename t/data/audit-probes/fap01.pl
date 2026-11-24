sub repl { $_[0] = "gone" } my $o={}; repl($o); print ref($o) ? "obj" : $o, "\n";
