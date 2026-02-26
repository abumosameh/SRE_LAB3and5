# **Lab 5: Researching and Implementing Scaling Patterns**

**Student Name:** Anas Abu Mosameh 

**Instructor Name:** Rahul Bahl

**GitHub Repository Link:** https://github.com/abumosameh/SRE\_LAB3and5/tree/lab5

## **Part 1: Research on Scaling Patterns**

### **1\. Vertical vs. Horizontal Scaling**

When an application gets too much traffic, there are two main ways to make it handle the load: scaling vertically or scaling horizontally.

**Vertical Scaling (Scaling Up):**

* **What it is:** Adding more power (CPU, RAM) to an existing server.  
* **When to use it:** When your application is hard to split across multiple servers, like a traditional relational database (e.g., a single massive MySQL server).  
* **Cost:** It gets very expensive quickly. High-end servers cost a lot more than several small ones.  
* **Limitations:** There is a hardware ceiling. Eventually, you can't buy a bigger server. Also, upgrading usually requires downtime (rebooting the server).  
* **Real-world example:** StackOverflow famously ran for a long time on just a few massive, vertically scaled SQL servers because it kept their architecture simple.

**Horizontal Scaling (Scaling Out):**

* **What it is:** Adding more servers to a group so they share the workload.  
* **When to use it:** For web servers, APIs, and microservices.  
* **Cost:** Much more flexible. You pay for cheaper, smaller instances and only run as many as you need.  
* **Limitations:** Your software has to be built to handle it. You can't store local sessions on one server if the user's next click goes to a different server.  
* **Real-world example:** Netflix uses horizontal scaling extensively. They run thousands of small servers and can easily add more during peak watching hours.

**Cloud Support:**

AWS, Azure, and GCP make horizontal scaling very easy using "Auto Scaling Groups" and Load Balancers. You only pay for what you use. Vertical scaling in the cloud is just changing the "instance type" (like going from a t2.micro to an m5.large), but it usually requires a quick restart.

### **2\. Caching Strategies**

Caching means storing frequently used data in a fast, temporary storage location so you don't have to fetch it from the slower main database every time.

* **CDN Caching (Content Delivery Network):** Stores static files (images, CSS, videos) on servers geographically close to the user. It's great for media-heavy sites. It's not good for live, changing data.  
* **Application/In-Memory Caching (like Redis):** Stores database query results in RAM. It's super fast. Best used for things like user sessions or a "top 10 products" list. The limitation is that RAM is expensive, so you can't cache everything.  
* **Database Query Caching:** The database itself remembers the answer to a question it was just asked. Good for sites with lots of reading but very little writing.

**Cache Invalidation & Failures:**

Invalidation is hard—how do you know when to delete the cache so users see fresh data? A common approach is setting a "TTL" (Time to Live) so it deletes itself after a few minutes.

* **Real-world failure (Cache Stampede):** If a very popular cache key suddenly expires, thousands of user requests might hit the main database at the exact same millisecond to rebuild the cache. This can instantly crash the database.

### **3\. Database Scaling**

* **Read Replicas:** Creating exact copies of your database that can only be *read* from. Great for apps where people read a lot but post rarely (like a blog).  
* **Sharding:** Splitting a large database into smaller pieces based on a rule (e.g., users A-M on Server 1, N-Z on Server 2).  
* **Relational vs. NoSQL:** Relational databases (MySQL) are very hard to shard because data is heavily connected. Document databases (MongoDB) and Key-Value stores (Redis) are built specifically to spread across many servers easily.

## **Part 2: Hands-On Caching Implementation and Analysis**

*Note on the Hands-On Section: Since we don't have access to the AWS Learner Lab for this course, I've created and attached the complete Terraform configuration files to build this infrastructure. As we discussed back in Lab 3, submitting this Terraform code fulfills the hands-on requirements for this part of the lab.*

https://github.com/abumosameh/SRE\_LAB3and5/tree/lab5

For this part, I used Terraform to build an AWS environment. My setup includes an Application Load Balancer, an Auto Scaling Group of EC2 instances running a web app, a DynamoDB table for the main database, and an ElastiCache Redis cluster for the caching layer.

**Performance Analysis:**

* **Without caching:** Every time a user requests the product list, the web server has to ask DynamoDB. This takes a bit of time (around 50-100ms) and costs money for every read operation on DynamoDB. Under heavy load, the database could become a bottleneck.  
* **With caching:** The first user's request fetches from DynamoDB and saves the result in Redis. The next thousands of users get the data straight from Redis. The response time drops significantly (around 5-10ms), and the load on the database drops to almost zero.  
* **Invalidation Strategy:** For my app, I would use a Time-To-Live (TTL) of 60 seconds. The tradeoff here is that if a product price changes, users might see the old price for up to a minute. However, the benefit is that it keeps the database completely safe from traffic spikes.

## **Part 3: Scaling Analysis for a Real-World Application**

**Reference Application:** E-commerce platform (like a medium-sized clothing store).

* **Current State:** 1 Web Server, 1 MySQL Database. Getting slow during holiday sales.

**Scaling Strategy:**

1. **Web Tier:** Put the web server behind an AWS Application Load Balancer and put it in an Auto Scaling Group. Now we can have anywhere from 2 to 20 servers depending on traffic.  
2. **Database Tier:** Add Read Replicas. When customers are just browsing products, they read from the replicas. When they actually buy something, it writes to the main database.  
3. **Caching:** Use ElastiCache (Redis) to store user shopping carts and login sessions so they don't take up space in the main database.  
4. **Static Content:** Put all product images on AWS CloudFront (CDN) so images load instantly no matter where the customer lives.

**Handling Challenges:**

* *10x Read Traffic:* Handled easily by the CDN and the database read replicas.  
* *5x Write Traffic:* This is harder. We might need to upgrade the main database vertically (bigger server) or move the checkout system to a fast NoSQL database like DynamoDB.  
* *Implementation Order:* I would implement the CDN and Redis cache first because they require the least changes to the main code and solve the biggest performance issues instantly.

## **Bonus Challenge: Auto-Scaling**

I implemented Auto-Scaling directly into my Terraform code (see compute.tf in the repo).

* I created CloudWatch alarms that monitor CPU usage.  
* If the average CPU of the servers goes over 70% for a few minutes, it triggers a "scale-up" policy to add another server.  
* If the CPU drops below 30%, it triggers a "scale-down" policy to remove a server and save money.  
* There is a slight delay (cooldown period of 300 seconds) to make sure the system doesn't spin up too many servers at once while waiting for the new ones to boot up.

## **Final Reflection**

Through researching and implementing these scaling patterns, I learned that scaling an application is rarely just a matter of "buying a bigger server." Every application has a bottleneck, and fixing performance issues is about finding that specific bottleneck and applying the right pattern.

For example, I originally thought horizontal scaling was always the answer. However, learning about databases showed me that adding more web servers doesn't help if your single database is the thing crashing. In that case, caching and read replicas are actually the solution, not more web servers.

The hands-on portion with Terraform really helped solidify this. Actually building a Load Balancer, an Auto Scaling Group, and a Redis Cache showed me how all these pieces connect. In a real-world scenario, I would definitely start by adding a CDN and a Redis cache before doing anything complicated with the database, because caching is relatively easy to implement and gives a massive performance boost. I also realized how important CloudWatch monitoring is; if you don't know your CPU is hitting 90%, you won't know that you need to scale until your website has already crashed.

**Thanks, \-Anas** 