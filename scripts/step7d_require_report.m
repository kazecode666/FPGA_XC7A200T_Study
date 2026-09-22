function step7d_require_report(file,marker)
assert(isfile(file),'Step7D:MissingReport','Missing fresh report: %s',file);
assert(contains(fileread(file),marker),'Step7D:MissingGate','Missing fresh gate: %s',marker);
end
