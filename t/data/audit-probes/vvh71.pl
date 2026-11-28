eval { nosuch() }; print $@ =~ /Undefined subroutine/ ? "undefsub" : "no", "\n";
