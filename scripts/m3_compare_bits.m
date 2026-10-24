function result=m3_compare_bits(expected,actual)
% 原始二进制/hex字符串比较；绝不经double数值转换。
a=string(expected);b=string(actual);
assert(isequal(size(a),size(b)),'M3:BIT_COUNT','Expected/observed word counts differ.');
different=a~=b;first=find(different,1);result=struct('pass',~any(different,'all'), ...
    'words',numel(a),'word_mismatch',nnz(different),'first_mismatch',first);
if ~result.pass
    error('M3:BIT_MISMATCH','Raw word mismatch index%d expected%s observed%s.', ...
        first,a(first),b(first));
end
end
