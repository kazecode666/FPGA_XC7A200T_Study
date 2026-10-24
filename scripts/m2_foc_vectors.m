function u=m2_foc_vectors
% 算法向量含非物理不平衡输入，区别于电机闭环场景。
rng(20261024,'twister');N=12000;u=zeros(N,9);u(:,1:3)=4*rand(N,3)-2;u(:,4)=linspace(-8*pi,8*pi,N)';u(:,5)=80*sin((1:N)'/131);u(:,6:7)=4*rand(N,2)-2;u(:,9)=48;u(1:200,:)=0;u(1:200,9)=48;u(:,8)=double(mod((1:N)',311)<3);
% Zero vector, tiny currents, exact angle boundaries and six sector sides.
theta=[0 2*pi -2*pi 1e-12 -1e-12];for k=1:numel(theta),j=201+10*k;u(j:j+9,1:3)=1e-12;u(j:j+9,4)=theta(k);end
for k=0:5,for side=[-1 0 1],j=300+100*k+10*(side+1);u(j:j+9,1:3)=0;u(j:j+9,4)=k*pi/3+side*1e-8;u(j:j+9,5)=0;u(j:j+9,6)=0;u(j:j+9,7)=.5;u(j:j+9,8)=0;end;end
u(2000:3000,1:3)=0;u(2000:3000,6:7)=2;u(3001:4000,6:7)=0;u(4001:4010,8)=1;u(5000:6000,1:3)=1e-7;u(5000:6000,6:7)=1e-7;
end
