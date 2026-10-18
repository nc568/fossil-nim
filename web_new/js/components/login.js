// login.js - Modern Login component with CSRF and auth session handling
registerComponent('login', (props) => {
  const c = new Component('login', props);

  c.render = () => {
    const query = c.props.query || {};
    const redirect = query.redirect || '/';
    return `
      <div style="display:flex; justify-content:center; align-items:center; min-height:60vh; padding:1rem">
        <div class="card" style="max-width:400px; width:100%; padding:2rem; box-shadow:0 4px 12px rgba(0,0,0,0.1); border-radius:8px">
          <h1 class="text-center" style="margin-bottom:1.5rem">🔐 Login</h1>
          <form id="login-form" method="post" action="/login">
            <input type="hidden" name="redirect" value="${redirect}">
            <input type="hidden" name="csrf" id="login-csrf" value="">
            <div class="form-group" style="margin-bottom:1rem">
              <label class="form-label" style="display:block; margin-bottom:0.25rem; font-weight:600">Username</label>
              <input name="user" id="login-user" class="form-input" placeholder="admin" required autofocus style="width:100%; padding:0.6rem; border:1px solid #ced4da; border-radius:4px">
            </div>
            <div class="form-group" style="margin-bottom:1rem">
              <label class="form-label" style="display:block; margin-bottom:0.25rem; font-weight:600">Password</label>
              <input name="password" id="login-pass" type="password" class="form-input" placeholder="admin123" required style="width:100%; padding:0.6rem; border:1px solid #ced4da; border-radius:4px">
            </div>
            <button type="submit" id="login-submit" class="btn btn-primary w-full" style="width:100%; padding:0.75rem; background:#0d6efd; color:#fff; border:none; border-radius:4px; font-size:1rem; cursor:pointer">Login</button>
            <div id="login-result" style="margin-top:1rem"></div>
          </form>
          <div class="text-center mt-4" style="margin-top:1.5rem; text-align:center">
            <a href="/" data-link style="color:#0d6efd; text-decoration:none">← Back to Home</a>
          </div>
        </div>
      </div>
    `;
  };

  c.afterRender = async () => {
    const csrfInput = document.getElementById('login-csrf');

    // Pre-fetch CSRF token
    try {
      const res = await fetch('/api/v1/csrf');
      if (res.ok) {
        const data = await res.json();
        const token = data?.data?.csrf;
        if (token && csrfInput) {
          csrfInput.value = token;
        }
      }
    } catch (e) {
      console.warn('Could not pre-fetch CSRF token:', e);
    }

    const form = document.getElementById('login-form');
    if (!form) return;

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const user = form.user.value.trim();
      const password = form.password.value;
      const redirect = form.redirect.value || '/';
      let csrf = csrfInput ? csrfInput.value : '';

      const resultEl = document.getElementById('login-result');
      if (resultEl) {
        resultEl.innerHTML = '<div style="text-align:center; padding:0.5rem; color:#6c757d">Logging in...</div>';
      }

      // If CSRF token is not present yet, fetch now
      if (!csrf) {
        try {
          const resCsrf = await fetch('/api/v1/csrf');
          if (resCsrf.ok) {
            const dataCsrf = await resCsrf.json();
            csrf = dataCsrf?.data?.csrf || '';
            if (csrfInput) csrfInput.value = csrf;
          }
        } catch (_) {}
      }

      try {
        const bodyData = 'user=' + encodeURIComponent(user) +
                         '&password=' + encodeURIComponent(password) +
                         '&redirect=' + encodeURIComponent(redirect) +
                         '&csrf=' + encodeURIComponent(csrf);

        const res = await fetch('/login', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'X-CSRF-Token': csrf
          },
          body: bodyData
        });

        const text = await res.text();
        let isSuccess = false;
        let userName = user;

        try {
          const json = JSON.parse(text);
          if (json.ok) {
            isSuccess = true;
            userName = json.user || user;
          }
        } catch (_) {
          if (res.ok && (text.includes('Welcome') || text.includes('Login Success'))) {
            isSuccess = true;
          }
        }

        if (isSuccess) {
          localStorage.setItem('fossil_user', userName);
          localStorage.setItem('fossil_token', 'session-active');
          if (window.app) {
            window.app.state.currentUser = userName;
            window.app.state.isAuthenticated = true;
            window.app.updateAuthUI();
          }
          if (resultEl) {
            resultEl.innerHTML = '<div style="padding:10px; background:#d4edda; color:#155724; border-radius:4px; text-align:center">✓ Welcome, ' + userName + '! Redirecting...</div>';
          }
          setTimeout(() => {
            if (window.app && window.app.navigate) {
              window.app.navigate(redirect);
            } else {
              window.location.href = redirect;
            }
          }, 600);
        } else {
          let errMsg = 'Login failed';
          try {
            const errJson = JSON.parse(text);
            if (errJson.error) errMsg = errJson.error;
          } catch (_) {
            if (text.includes('Invalid credentials')) errMsg = 'Invalid username or password';
            else if (text.includes('CSRF')) errMsg = 'Invalid CSRF token. Please retry.';
            else if (text.includes('Invalid login')) errMsg = 'Invalid login credentials';
          }
          if (resultEl) {
            resultEl.innerHTML = '<div style="padding:10px; background:#f8d7da; color:#721c24; border-radius:4px; text-align:center">' + errMsg + '</div>';
          }
        }
      } catch (err) {
        if (resultEl) {
          resultEl.innerHTML = '<div style="padding:10px; background:#f8d7da; color:#721c24; border-radius:4px; text-align:center">Error: ' + err.message + '</div>';
        }
      }
    });
  };

  return c;
});
console.log('📦 login component loaded');
