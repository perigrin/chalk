my $r = eval { my $u; $u->m; 1 }; print $r ? "ok" : "died", $@ =~ /Can't call method "m" on an undefined value/ ? "msg" : "other", "\n";
