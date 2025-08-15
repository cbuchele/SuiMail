// SuiMail Walrus Site JavaScript
class SuiMailApp {
    constructor() {
        this.init();
    }

    init() {
        this.bindEvents();
        this.initSmoothScrolling();
        this.initAnimations();
        this.initWalletConnection();
    }

    bindEvents() {
        // Navigation
        document.querySelectorAll('.nav-link').forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const targetId = link.getAttribute('href').substring(1);
                this.scrollToSection(targetId);
            });
        });

        // Header actions
        const connectWalletBtn = document.getElementById('connect-wallet');
        const launchAppBtn = document.getElementById('launch-app');
        const getStartedBtn = document.getElementById('get-started');
        const learnMoreBtn = document.getElementById('learn-more');
        const createMailboxBtn = document.getElementById('create-mailbox');
        const viewDemoBtn = document.getElementById('view-demo');

        if (connectWalletBtn) {
            connectWalletBtn.addEventListener('click', () => this.connectWallet());
        }

        if (launchAppBtn) {
            launchAppBtn.addEventListener('click', () => this.launchApp());
        }

        if (getStartedBtn) {
            getStartedBtn.addEventListener('click', () => this.scrollToSection('features'));
        }

        if (learnMoreBtn) {
            learnMoreBtn.addEventListener('click', () => this.scrollToSection('how-it-works'));
        }

        if (createMailboxBtn) {
            createMailboxBtn.addEventListener('click', () => this.createMailbox());
        }

        if (viewDemoBtn) {
            viewDemoBtn.addEventListener('click', () => this.showEmailDemo());
        }

        // Modal handling
        const modal = document.getElementById('email-app-modal');
        const closeModalBtn = document.getElementById('close-modal');

        if (closeModalBtn) {
            closeModalBtn.addEventListener('click', () => this.closeModal());
        }

        if (modal) {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    this.closeModal();
                }
            });
        }

        // Email interface interactions
        this.initEmailInterface();

        // Smooth scroll for anchor links
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', (e) => {
                e.preventDefault();
                const targetId = anchor.getAttribute('href').substring(1);
                this.scrollToSection(targetId);
            });
        });
    }

    initSmoothScrolling() {
        // Smooth scrolling for all internal links
        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', (e) => {
                e.preventDefault();
                const targetId = anchor.getAttribute('href').substring(1);
                this.scrollToSection(targetId);
            });
        });
    }

    scrollToSection(sectionId) {
        const section = document.getElementById(sectionId);
        if (section) {
            const headerHeight = document.querySelector('.header').offsetHeight;
            const targetPosition = section.offsetTop - headerHeight - 20;
            
            window.scrollTo({
                top: targetPosition,
                behavior: 'smooth'
            });
        }
    }

    initAnimations() {
        // Intersection Observer for fade-in animations
        const observerOptions = {
            threshold: 0.1,
            rootMargin: '0px 0px -50px 0px'
        };

        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('animate-in');
                }
            });
        }, observerOptions);

        // Observe elements for animation
        document.querySelectorAll('.feature-card, .step, .feature-item').forEach(el => {
            observer.observe(el);
        });

        // Add animation classes
        this.addAnimationClasses();
    }

    addAnimationClasses() {
        // Add CSS animation classes
        const style = document.createElement('style');
        style.textContent = `
            .feature-card, .step, .feature-item {
                opacity: 0;
                transform: translateY(30px);
                transition: all 0.6s ease-out;
            }
            
            .animate-in {
                opacity: 1;
                transform: translateY(0);
            }
            
            .feature-card:nth-child(1) { transition-delay: 0.1s; }
            .feature-card:nth-child(2) { transition-delay: 0.2s; }
            .feature-card:nth-child(3) { transition-delay: 0.3s; }
            .feature-card:nth-child(4) { transition-delay: 0.4s; }
            .feature-card:nth-child(5) { transition-delay: 0.5s; }
            .feature-card:nth-child(6) { transition-delay: 0.6s; }
            
            .step:nth-child(1) { transition-delay: 0.1s; }
            .step:nth-child(2) { transition-delay: 0.2s; }
            .step:nth-child(3) { transition-delay: 0.3s; }
            .step:nth-child(4) { transition-delay: 0.4s; }
        `;
        document.head.appendChild(style);
    }

    initWalletConnection() {
        // Check if wallet is already connected
        this.checkWalletConnection();
    }

    async checkWalletConnection() {
        // Check for Sui wallet connection
        if (typeof window.suiWallet !== 'undefined') {
            try {
                const accounts = await window.suiWallet.getAccounts();
                if (accounts && accounts.length > 0) {
                    this.updateWalletButton(accounts[0]);
                }
            } catch (error) {
                console.log('No wallet connected');
            }
        }
    }

    async connectWallet() {
        try {
            if (typeof window.suiWallet !== 'undefined') {
                const accounts = await window.suiWallet.requestAccounts();
                if (accounts && accounts.length > 0) {
                    this.updateWalletButton(accounts[0]);
                    this.showNotification('Wallet connected successfully!', 'success');
                }
            } else {
                this.showNotification('Please install a Sui wallet extension', 'warning');
                this.openWalletInstallGuide();
            }
        } catch (error) {
            console.error('Wallet connection failed:', error);
            this.showNotification('Failed to connect wallet', 'error');
        }
    }

    updateWalletButton(account) {
        const connectWalletBtn = document.getElementById('connect-wallet');
        if (connectWalletBtn) {
            const shortAddress = `${account.slice(0, 6)}...${account.slice(-4)}`;
            connectWalletBtn.textContent = shortAddress;
            connectWalletBtn.classList.add('connected');
            connectWalletBtn.classList.remove('btn-secondary');
            connectWalletBtn.classList.add('btn-success');
        }
    }

    launchApp() {
        // Check if wallet is connected
        if (document.querySelector('#connect-wallet.connected')) {
            this.showEmailDemo();
        } else {
            this.showNotification('Please connect your wallet first', 'warning');
            this.connectWallet();
        }
    }

    showEmailDemo() {
        const modal = document.getElementById('email-app-modal');
        if (modal) {
            modal.style.display = 'block';
            document.body.style.overflow = 'hidden';
        }
    }

    closeModal() {
        const modal = document.getElementById('email-app-modal');
        if (modal) {
            modal.style.display = 'none';
            document.body.style.overflow = 'auto';
        }
    }

    createMailbox() {
        if (document.querySelector('#connect-wallet.connected')) {
            this.showNotification('Redirecting to mailbox creation...', 'info');
            // Here you would integrate with the actual SuiMail app
            setTimeout(() => {
                this.showEmailDemo();
            }, 1500);
        } else {
            this.showNotification('Please connect your wallet first', 'warning');
            this.connectWallet();
        }
    }

    initEmailInterface() {
        // Email list interactions
        document.querySelectorAll('.email-item').forEach(item => {
            item.addEventListener('click', () => {
                this.selectEmail(item);
            });
        });

        // Compose button
        const composeBtn = document.querySelector('.compose-btn');
        if (composeBtn) {
            composeBtn.addEventListener('click', () => {
                this.showComposeEmail();
            });
        }

        // Sidebar navigation
        document.querySelectorAll('.sidebar-nav .nav-item').forEach(item => {
            item.addEventListener('click', (e) => {
                e.preventDefault();
                this.switchEmailFolder(item);
            });
        });
    }

    selectEmail(emailItem) {
        // Remove active class from all emails
        document.querySelectorAll('.email-item').forEach(item => {
            item.classList.remove('selected');
        });

        // Add active class to selected email
        emailItem.classList.add('selected');

        // Mark as read
        emailItem.classList.remove('unread');

        // Show email content (in a real app, this would load the email)
        this.showEmailContent(emailItem);
    }

    showEmailContent(emailItem) {
        // In a real app, this would display the email content
        const sender = emailItem.querySelector('.email-sender').textContent;
        const subject = emailItem.querySelector('.email-subject').textContent;
        
        this.showNotification(`Loading email from ${sender}: ${subject}`, 'info');
    }

    switchEmailFolder(navItem) {
        // Remove active class from all nav items
        document.querySelectorAll('.sidebar-nav .nav-item').forEach(item => {
            item.classList.remove('active');
        });

        // Add active class to selected nav item
        navItem.classList.add('active');

        // Update email list based on folder
        const folderName = navItem.textContent.trim();
        this.loadFolderEmails(folderName);
    }

    loadFolderEmails(folderName) {
        // In a real app, this would load emails from the selected folder
        this.showNotification(`Loading ${folderName} folder...`, 'info');
    }

    showComposeEmail() {
        // In a real app, this would open the compose email interface
        this.showNotification('Opening compose email...', 'info');
    }

    showNotification(message, type = 'info') {
        // Create notification element
        const notification = document.createElement('div');
        notification.className = `notification notification-${type}`;
        notification.innerHTML = `
            <div class="notification-content">
                <span class="notification-message">${message}</span>
                <button class="notification-close">&times;</button>
            </div>
        `;

        // Add notification styles
        if (!document.querySelector('#notification-styles')) {
            const style = document.createElement('style');
            style.id = 'notification-styles';
            style.textContent = `
                .notification {
                    position: fixed;
                    top: 100px;
                    right: 20px;
                    background: white;
                    border-radius: 8px;
                    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
                    border-left: 4px solid #6366f1;
                    z-index: 3000;
                    max-width: 400px;
                    animation: slideIn 0.3s ease-out;
                }
                
                .notification-success { border-left-color: #10b981; }
                .notification-warning { border-left-color: #f59e0b; }
                .notification-error { border-left-color: #ef4444; }
                .notification-info { border-left-color: #6366f1; }
                
                .notification-content {
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    padding: 1rem;
                }
                
                .notification-message {
                    color: #1f2937;
                    font-weight: 500;
                }
                
                .notification-close {
                    background: none;
                    border: none;
                    font-size: 1.5rem;
                    cursor: pointer;
                    color: #6b7280;
                    margin-left: 1rem;
                }
                
                .notification-close:hover {
                    color: #1f2937;
                }
                
                @keyframes slideIn {
                    from {
                        transform: translateX(100%);
                        opacity: 0;
                    }
                    to {
                        transform: translateX(0);
                        opacity: 1;
                    }
                }
            `;
            document.head.appendChild(style);
        }

        // Add to page
        document.body.appendChild(notification);

        // Auto-remove after 5 seconds
        setTimeout(() => {
            this.removeNotification(notification);
        }, 5000);

        // Close button functionality
        const closeBtn = notification.querySelector('.notification-close');
        closeBtn.addEventListener('click', () => {
            this.removeNotification(notification);
        });
    }

    removeNotification(notification) {
        notification.style.animation = 'slideOut 0.3s ease-in';
        setTimeout(() => {
            if (notification.parentNode) {
                notification.parentNode.removeChild(notification);
            }
        }, 300);
    }

    openWalletInstallGuide() {
        // Show wallet installation guide
        const guide = `
            <div class="wallet-guide">
                <h3>Install a Sui Wallet</h3>
                <p>To use SuiMail, you need a Sui wallet. Here are some popular options:</p>
                <ul>
                    <li><a href="https://suiet.app/" target="_blank">Suiet Wallet</a></li>
                    <li><a href="https://chrome.google.com/webstore/detail/sui-wallet/opcgpfmipidbgpenhmajoajpbobppdil" target="_blank">Sui Wallet Extension</a></li>
                    <li><a href="https://martianwallet.com/" target="_blank">Martian Wallet</a></li>
                </ul>
                <button class="btn btn-primary" onclick="this.parentElement.remove()">Got it!</button>
            </div>
        `;

        const guideElement = document.createElement('div');
        guideElement.innerHTML = guide;
        guideElement.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: white;
            padding: 2rem;
            border-radius: 12px;
            box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1);
            z-index: 3000;
            max-width: 500px;
            text-align: center;
        `;

        document.body.appendChild(guideElement);
    }

    // Utility functions
    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }

    throttle(func, limit) {
        let inThrottle;
        return function() {
            const args = arguments;
            const context = this;
            if (!inThrottle) {
                func.apply(context, args);
                inThrottle = true;
                setTimeout(() => inThrottle = false, limit);
            }
        };
    }
}

// Initialize the app when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new SuiMailApp();
});

// Add some additional utility functions
window.SuiMailUtils = {
    // Format wallet address
    formatAddress: (address, length = 6) => {
        if (!address) return '';
        return `${address.slice(0, length)}...${address.slice(-length)}`;
    },

    // Format file size
    formatFileSize: (bytes) => {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    },

    // Format timestamp
    formatTimestamp: (timestamp) => {
        const date = new Date(timestamp);
        const now = new Date();
        const diff = now - date;
        
        if (diff < 60000) return 'Just now';
        if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
        if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
        if (diff < 2592000000) return `${Math.floor(diff / 86400000)}d ago`;
        
        return date.toLocaleDateString();
    },

    // Validate email format
    validateEmail: (email) => {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    },

    // Copy to clipboard
    copyToClipboard: async (text) => {
        try {
            await navigator.clipboard.writeText(text);
            return true;
        } catch (err) {
            // Fallback for older browsers
            const textArea = document.createElement('textarea');
            textArea.value = text;
            document.body.appendChild(textArea);
            textArea.select();
            document.execCommand('copy');
            document.body.removeChild(textArea);
            return true;
        }
    }
};

// Add global error handling
window.addEventListener('error', (event) => {
    console.error('Global error:', event.error);
});

// Add unhandled promise rejection handling
window.addEventListener('unhandledrejection', (event) => {
    console.error('Unhandled promise rejection:', event.reason);
});