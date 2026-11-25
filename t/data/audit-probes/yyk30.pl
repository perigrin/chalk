my $r = eval { my $u = "NoSuch"; $u->m; 1 }; print $r ? "ok" : "died", $@ =~ /Can't locate object method "m" via package "NoSuch"/ ? "msg" : "other", "\n";
