my @a = (1,2,3); my $r = eval { $a[-5] = 1; 1 }; print $r ? "ok" : "died", $@ =~ /Modification of non-creatable array value attempted, subscript -5/ ? "msg" : "other", "\n";
