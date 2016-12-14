pkg load queueingnS = 5 % number of serversnT = 32 % number of threadsnK = 1 + 1 + nS + 1 % network + LoadBalancer + Worker + network% [U, R, Q, X, G] = qncsmva (N, S, V, [m, [Z]])% N -- Population size (number of requests in the system, N ≥ 0). If N == 0, this function returns U = R = Q = X = 0N = 180% S -- S(k) is the mean service time at center k (S(k) ≥ 0).S = zeros(nK, 1)S(1) = 2.843164 / 1000 % ms -> sS(2) = 0.004557388 / 1000 % ms -> sS(3:nK-1) = 4.213177 / 1000 % ms -> sS(nK) = S(1)% V -- V(k) is the average number of visits to service center k (V(k) ≥ 0).V = ones(nK, 1)V(3:nK-1) = 1 / nS% m -- m(k) is the number of servers at center k (if m is a scalar, all centers have that number of servers).% If m(k) < 1, center k is a delay center (IS); otherwise it is a regular queueing center (FCFS, LCFS-PR or PS) with m(k) servers.% Default is m(k) = 1 for all k (each service center has a single server).m = ones(nK, 1)m(1) = 0 # delay centerm(3:nK-1) = nTm(nK) = 0 # delay center% Z -- External delay for customers (Z ≥ 0). Default is 0.Z = 0% ---- Results ----[U, R, Q, X, G] = qncsmva (N, S, V, m, Z);% U -- If k is a FCFS, LCFS-PR or PS node (m(k) ≥ 1), then U(k) is the utilization of center k, 0 ≤ U(k) ≤ 1. If k is an IS node (m(k) < 1), then U(k) is the traffic intensity defined as X(k)*S(k). In this case the value of U(k) may be greater than one.% R -- R(k) is the response time at center k. The Residence Time at center k is R(k) * V(k). The system response time Rsys can be computed either as Rsys = N/Xsys - Z or as Rsys = dot(R,V)% Q -- Q(k) is the average number of requests at center k. The number of requests in the system can be computed either as sum(Q), or using the formula N-Xsys*Z.% X -- X(k) is the throughput of center k. The system throughput Xsys can be computed as Xsys = X(1) / V(1)% G -- Normalization constants. G(n+1) corresponds to the value of the normalization constant G(n), n=0, …, N as array indexes in Octave start from 1. G(n) can be used in conjunction with the BCMP theorem to compute steady-state probabilities.Qr = round(Q)printf("Number of jobs:\n\t%d between client and LoadBalancer\n\t%d in LoadBalancer \n\t%d total in all MiddlewareComponents\n\t%d between MiddlewareComponent and client\n", Qr(1), Qr(2), sum(Qr(3:nK-1)), Qr(nK))