eval { die }; print $@ =~ /^Died at .* line 1\.$/ ? "ok" : "no:$@", "\n"; eval { $@ = ""; die }; print $@ =~ /^Died/ ? "ok" : "no", "\n";
