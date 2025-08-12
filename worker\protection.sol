// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title GigWorkerProtection
 * @dev A smart contract to protect gig workers through escrow payments, dispute resolution, and reputation system
 */
contract GigWorkerProtection {
    
    enum JobStatus { Created, InProgress, Completed, Disputed, Resolved }
    
    struct Job {
        uint256 jobId;
        address client;
        address worker;
        uint256 payment;
        string jobDescription;
        uint256 deadline;
        JobStatus status;
        uint256 createdAt;
        bool paymentReleased;
    }
    
    struct Worker {
        address workerAddress;
        uint256 totalEarnings;
        uint256 jobsCompleted;
        uint256 reputation; // 0-100 rating
        bool isRegistered;
    }
    
    struct Dispute {
        uint256 jobId;
        address initiator;
        string reason;
        uint256 createdAt;
        bool resolved;
        address winner; // Who won the dispute
    }
    
    mapping(uint256 => Job) public jobs;
    mapping(address => Worker) public workers;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public workerJobs;
    mapping(address => uint256[]) public clientJobs;
    
    uint256 public nextJobId = 1;
    uint256 public platformFeePercentage = 5; // 5% platform fee
    address public platformOwner;
    
    event JobCreated(uint256 indexed jobId, address indexed client, address indexed worker, uint256 payment);
    event JobCompleted(uint256 indexed jobId, address indexed worker);
    event PaymentReleased(uint256 indexed jobId, address indexed worker, uint256 amount);
    event DisputeRaised(uint256 indexed jobId, address indexed initiator, string reason);
    event DisputeResolved(uint256 indexed jobId, address indexed winner, uint256 compensation);
    event WorkerRegistered(address indexed worker);
    
    modifier onlyPlatformOwner() {
        require(msg.sender == platformOwner, "Only platform owner can call this function");
        _;
    }
    
    modifier onlyJobParticipant(uint256 _jobId) {
        require(
            msg.sender == jobs[_jobId].client || msg.sender == jobs[_jobId].worker,
            "Only job client or worker can call this function"
        );
        _;
    }
    
    constructor() {
        platformOwner = msg.sender;
    }
    
    /**
     * @dev Register as a gig worker on the platform
     */
    function registerWorker() external {
        require(!workers[msg.sender].isRegistered, "Worker already registered");
        
        workers[msg.sender] = Worker({
            workerAddress: msg.sender,
            totalEarnings: 0,
            jobsCompleted: 0,
            reputation: 50, // Start with neutral reputation
            isRegistered: true
        });
        
        emit WorkerRegistered(msg.sender);
    }
    
    /**
     * @dev Create a new job with escrow payment
     * @param _worker Address of the worker assigned to this job
     * @param _jobDescription Description of the work to be done
     * @param _deadline Unix timestamp for job completion deadline
     */
    function createJob(
        address _worker,
        string memory _jobDescription,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Payment must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(workers[_worker].isRegistered, "Worker must be registered");
        require(_worker != msg.sender, "Client cannot be the worker");
        
        uint256 jobId = nextJobId++;
        
        jobs[jobId] = Job({
            jobId: jobId,
            client: msg.sender,
            worker: _worker,
            payment: msg.value,
            jobDescription: _jobDescription,
            deadline: _deadline,
            status: JobStatus.Created,
            createdAt: block.timestamp,
            paymentReleased: false
        });
        
        workerJobs[_worker].push(jobId);
        clientJobs[msg.sender].push(jobId);
        
        emit JobCreated(jobId, msg.sender, _worker, msg.value);
    }
    
    /**
     * @dev Mark job as completed by worker
     * @param _jobId ID of the job to be marked as completed
     */
    function completeJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        require(job.worker == msg.sender, "Only assigned worker can complete job");
        require(job.status == JobStatus.Created || job.status == JobStatus.InProgress, "Job cannot be completed");
        require(!job.paymentReleased, "Payment already released");
        
        job.status = JobStatus.Completed;
        
        emit JobCompleted(_jobId, msg.sender);
    }
    
    /**
     * @dev Release payment to worker (can be called by client or automatically after deadline + grace period)
     * @param _jobId ID of the job for payment release
     */
    function releasePayment(uint256 _jobId) external onlyJobParticipant(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.status == JobStatus.Completed, "Job must be completed first");
        require(!job.paymentReleased, "Payment already released");
        
        // Allow automatic release if deadline + 7 days have passed
        bool canAutoRelease = block.timestamp > (job.deadline + 7 days);
        bool isClient = msg.sender == job.client;
        
        require(isClient || canAutoRelease, "Only client can release payment or wait for auto-release");
        
        job.paymentReleased = true;
        
        // Calculate platform fee and worker payment
        uint256 platformFee = (job.payment * platformFeePercentage) / 100;
        uint256 workerPayment = job.payment - platformFee;
        
        // Update worker stats
        workers[job.worker].totalEarnings += workerPayment;
        workers[job.worker].jobsCompleted += 1;
        
        // Transfer payments
        payable(job.worker).transfer(workerPayment);
        payable(platformOwner).transfer(platformFee);
        
        emit PaymentReleased(_jobId, job.worker, workerPayment);
    }
    
    /**
     * @dev Raise a dispute for a job
     * @param _jobId ID of the job in dispute
     * @param _reason Reason for the dispute
     */
    function raiseDispute(uint256 _jobId, string memory _reason) external onlyJobParticipant(_jobId) {
        Job storage job = jobs[_jobId];
        require(job.status != JobStatus.Disputed, "Dispute already raised");
        require(!job.paymentReleased, "Cannot dispute after payment release");
        require(disputes[_jobId].createdAt == 0, "Dispute already exists");
        
        job.status = JobStatus.Disputed;
        
        disputes[_jobId] = Dispute({
            jobId: _jobId,
            initiator: msg.sender,
            reason: _reason,
            createdAt: block.timestamp,
            resolved: false,
            winner: address(0)
        });
        
        emit DisputeRaised(_jobId, msg.sender, _reason);
    }
    
    // View functions for frontend integration
    function getJob(uint256 _jobId) external view returns (
        address client,
        address worker,
        uint256 payment,
        string memory jobDescription,
        uint256 deadline,
        JobStatus status,
        uint256 createdAt,
        bool paymentReleased
    ) {
        Job memory job = jobs[_jobId];
        return (
            job.client,
            job.worker,
            job.payment,
            job.jobDescription,
            job.deadline,
            job.status,
            job.createdAt,
            job.paymentReleased
        );
    }
    
    function getWorkerStats(address _worker) external view returns (
        uint256 totalEarnings,
        uint256 jobsCompleted,
        uint256 reputation,
        bool isRegistered
    ) {
        Worker memory worker = workers[_worker];
        return (
            worker.totalEarnings,
            worker.jobsCompleted,
            worker.reputation,
            worker.isRegistered
        );
    }
    
    function getWorkerJobs(address _worker) external view returns (uint256[] memory) {
        return workerJobs[_worker];
    }
    
    function getClientJobs(address _client) external view returns (uint256[] memory) {
        return clientJobs[_client];
    }
    
    function getDispute(uint256 _jobId) external view returns (
        address initiator,
        string memory reason,
        uint256 createdAt,
        bool resolved,
        address winner
    ) {
        Dispute memory dispute = disputes[_jobId];
        return (
            dispute.initiator,
            dispute.reason,
            dispute.createdAt,
            dispute.resolved,
            dispute.winner
        );
    }
    
    // Platform management functions (can be extended)
    function updatePlatformFee(uint256 _newFeePercentage) external onlyPlatformOwner {
        require(_newFeePercentage <= 10, "Platform fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
    
    // Emergency function to resolve disputes (in future versions, this could be DAO-governed)
    function resolveDispute(uint256 _jobId, address _winner, uint256 _compensation) external onlyPlatformOwner {
        require(disputes[_jobId].createdAt > 0, "Dispute does not exist");
        require(!disputes[_jobId].resolved, "Dispute already resolved");
        require(!jobs[_jobId].paymentReleased, "Payment already released");
        
        Job storage job = jobs[_jobId];
        Dispute storage dispute = disputes[_jobId];
        
        dispute.resolved = true;
        dispute.winner = _winner;
        job.status = JobStatus.Resolved;
        job.paymentReleased = true;
        
        // Transfer compensation to winner
        if (_compensation > 0 && _compensation <= job.payment) {
            payable(_winner).transfer(_compensation);
            
            // If there's remaining payment, it could go to platform or be handled differently
            uint256 remaining = job.payment - _compensation;
            if (remaining > 0) {
                payable(platformOwner).transfer(remaining);
            }
        }
        
        emit DisputeResolved(_jobId, _winner, _compensation);
    }
}
