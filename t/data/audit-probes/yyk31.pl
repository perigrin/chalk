my $r = eval { my $u = {}; $u->m; 1 }; print $r ? "ok" : "died", $@ =~ /unblessed reference/ ? "msg" : "other", "\n";
